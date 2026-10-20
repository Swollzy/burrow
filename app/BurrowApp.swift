// Burrow.app: the window for Burrow. Every action runs the `burrow` command-line tool
// (bin/burrow), so the app and Terminal always do exactly the same thing.
//
// Built on the Mac by `burrow app` with the Command Line Tools' swiftc:
//   swiftc -O -swift-version 5 -parse-as-library -target <arch>-apple-macos13.0 BurrowApp.swift -o Burrow
// Needs macOS 13 or newer.

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Data from the CLI

struct LibraryApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bottle: String
    let steamAppID: String
    var isSteamGame: Bool { !steamAppID.isEmpty }
}

struct SteamGame: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DiskRow: Identifiable, Hashable {
    let id = UUID()
    let kind: String  // bottle, game, engine, other
    let name: String
    let kb: Double
}

struct ProcRow: Identifiable, Hashable {
    let id: String  // pid
    let bottle: String
    let name: String
    let kb: Double
}

struct BurrowStatus {
    var flags: [String: String] = [:]
    func has(_ key: String) -> Bool { flags[key] == "1" }
    var loaded: Bool { !flags.isEmpty }
}

func humanKB(_ kb: Double) -> String {
    if kb >= 1_048_576 { return String(format: "%.1f GB", kb / 1_048_576) }
    if kb >= 1024 { return String(format: "%.0f MB", kb / 1024) }
    return String(format: "%.0f KB", kb)
}

// MARK: - Model

final class BurrowModel: ObservableObject {
    @Published var status = BurrowStatus()
    @Published var apps: [LibraryApp] = []
    @Published var games: [SteamGame] = []
    @Published var disk: [DiskRow] = []
    @Published var diskTotal: Double = 0
    @Published var diskFree: Double = 0
    @Published var diskLoading = false
    @Published var procs: [ProcRow] = []

    // The long job shown in the console sheet (setup, turbo, installers…).
    @Published var showConsole = false
    @Published var consoleTitle = ""
    @Published var consoleText = ""
    @Published var jobRunning = false
    @Published var lastJobFailed = false

    let home: String
    let cli: String

    init() {
        let env = ProcessInfo.processInfo.environment
        home = env["BURROW_HOME"] ?? (NSHomeDirectory() + "/Library/Application Support/Burrow")
        cli = env["BURROW_CLI"] ?? (home + "/app/bin/burrow")
        refreshAll()
    }

    var cliExists: Bool { FileManager.default.fileExists(atPath: cli) }

    private func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [cli] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        return p
    }

    /// Runs a quick command off the main thread and hands its output back on the main thread.
    func capture(_ args: [String], done: @escaping (String) -> Void) {
        guard cliExists else { done(""); return }
        let p = makeProcess(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        DispatchQueue.global(qos: .userInitiated).async {
            var text = ""
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                text = String(decoding: data, as: UTF8.self)
            } catch {
                text = ""
            }
            DispatchQueue.main.async { done(text) }
        }
    }

    /// Starts something that keeps running on its own (a game, Steam). Output goes to Burrow's logs.
    func fire(_ args: [String]) {
        guard cliExists else { return }
        let p = makeProcess(args)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Runs a long job and streams its output into the console sheet.
    func runJob(_ title: String, _ args: [String], then: (() -> Void)? = nil) {
        guard !jobRunning else { showConsole = true; return }
        consoleTitle = title
        consoleText = ""
        lastJobFailed = false
        jobRunning = true
        showConsole = true
        guard cliExists else {
            consoleText = "Burrow's command-line tool is missing at:\n\(cli)\nRun install.sh again."
            jobRunning = false
            lastJobFailed = true
            return
        }
        let p = makeProcess(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consoleText += chunk }
        }
        p.terminationHandler = { [weak self] proc in
            // Children that outlive the job (wineserver, Steam) can keep the pipe open, so the
            // job ends when the burrow process exits, not at end of output.
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.availableData
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !rest.isEmpty { self.consoleText += String(decoding: rest, as: UTF8.self) }
                self.jobRunning = false
                self.lastJobFailed = proc.terminationStatus != 0
                self.consoleText += self.lastJobFailed
                    ? "\n✗ Stopped with an error. Use Copy to send this to Claude."
                    : "\n✓ Done."
                self.refreshAll()
                if !self.lastJobFailed { then?() }
            }
        }
        do {
            try p.run()
        } catch {
            consoleText = "Couldn't start burrow: \(error.localizedDescription)"
            jobRunning = false
            lastJobFailed = true
        }
    }

    // MARK: Refreshing

    func refreshAll() {
        refreshStatus()
        refreshApps()
        refreshGames()
        refreshMemory()
    }

    func refreshStatus() {
        capture(["status"]) { [weak self] out in
            var flags: [String: String] = [:]
            for pair in out.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { flags[String(kv[0])] = String(kv[1]) }
            }
            self?.status = BurrowStatus(flags: flags)
        }
    }

    func refreshApps() {
        capture(["apps", "--plain"]) { [weak self] out in
            self?.apps = out.split(separator: "\n").compactMap { line -> LibraryApp? in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 2 else { return nil }
                return LibraryApp(id: f[0], name: f[1], bottle: f.count > 2 ? f[2] : "",
                                  steamAppID: f.count > 3 ? f[3] : "")
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func refreshGames() {
        capture(["steam", "games", "--plain"]) { [weak self] out in
            self?.games = out.split(separator: "\n").compactMap { line -> SteamGame? in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 2 else { return nil }
                return SteamGame(id: f[0], name: f[1])
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func refreshMemory() {
        capture(["usage", "--ram", "--plain"]) { [weak self] out in
            self?.procs = out.split(separator: "\n").compactMap { line -> ProcRow? in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 5, f[0] == "PROC" else { return nil }
                return ProcRow(id: f[3], bottle: f[1], name: f[2], kb: Double(f[4]) ?? 0)
            }.sorted { $0.kb > $1.kb }
        }
    }

    func refreshDisk() {
        diskLoading = true
        capture(["usage", "--plain"]) { [weak self] out in
            guard let self = self else { return }
            var rows: [DiskRow] = []
            for line in out.split(separator: "\n") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                switch f.first ?? "" {
                case "DISK" where f.count >= 4: rows.append(DiskRow(kind: f[1], name: f[2], kb: Double(f[3]) ?? 0))
                case "TOTAL" where f.count >= 2: self.diskTotal = Double(f[1]) ?? 0
                case "FREE" where f.count >= 2: self.diskFree = Double(f[1]) ?? 0
                default: break
                }
            }
            self.disk = rows
            self.diskLoading = false
        }
    }

    // MARK: Actions

    func launch(_ app: LibraryApp, compat: Bool = false) {
        fire(["launch", app.id] + (compat ? ["--graphics", "compat"] : []))
    }

    func installProgram() {
        let panel = NSOpenPanel()
        panel.title = "Pick a Windows installer"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["exe", "msi"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runJob("Installing \(url.lastPathComponent)", ["install", url.path])
    }

    func makeShortcut(_ app: LibraryApp) {
        capture(["shortcut", app.id]) { _ in
            let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Burrow")
            NSWorkspace.shared.open(folder)
        }
    }

    func remove(_ app: LibraryApp) {
        capture(["remove", app.id]) { [weak self] _ in self?.refreshApps() }
    }

    func openSteam() { fire(["steam"]) }

    func installSteam() {
        runJob("Installing Windows Steam", ["steam", "install"]) { [weak self] in self?.openSteam() }
    }

    func syncSteam() {
        capture(["steam", "sync"]) { [weak self] _ in self?.refreshApps() }
    }

    func play(_ game: SteamGame) { fire(["steam", "play", game.id]) }

    func stopBottle(_ bottle: String) {
        capture(["kill", bottle]) { [weak self] _ in self?.refreshMemory() }
    }

    func stopAll() {
        capture(["kill"]) { [weak self] _ in self?.refreshMemory() }
    }

    func openFolder(_ sub: String = "") {
        NSWorkspace.shared.open(URL(fileURLWithPath: home + (sub.isEmpty ? "" : "/" + sub)))
    }

    /// Homebrew's installer asks for your password, so it has to run in Terminal.
    func installHomebrewInTerminal() {
        let cmd = "/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\""
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell"
        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

// MARK: - Views

@main
struct BurrowApp: App {
    @StateObject private var model = BurrowModel()

    var body: some Scene {
        WindowGroup("Burrow") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: BurrowModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            LibraryView(goToSetup: { tab = 3 })
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }.tag(0)
            SteamView()
                .tabItem { Label("Steam", systemImage: "gamecontroller") }.tag(1)
            UsageView()
                .tabItem { Label("Usage", systemImage: "internaldrive") }.tag(2)
            SetupView()
                .tabItem { Label("Setup", systemImage: "wrench.and.screwdriver") }.tag(3)
        }
        .padding()
        .sheet(isPresented: $model.showConsole) { ConsoleView().environmentObject(model) }
        .onAppear {
            if model.status.loaded && !model.status.has("setup") { tab = 3 }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: BurrowModel
    var goToSetup: () -> Void
    @State private var toRemove: LibraryApp?

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Windows programs").font(.title2).bold()
                Spacer()
                Button { model.refreshApps() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { model.installProgram() } label: { Label("Install Windows Program…", systemImage: "plus") }
                    .disabled(!model.status.has("setup"))
            }
            if model.status.loaded && !model.status.has("setup") {
                Banner(text: "Burrow needs to download Wine first.", button: "Go to Setup", action: goToSetup)
            } else if model.status.loaded && !model.status.has("turbo") {
                Banner(text: "Turbo graphics isn't built yet, so 3D games will be slow or won't start.",
                       button: "Go to Setup", action: goToSetup)
            }
            if model.apps.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("Nothing here yet.").font(.headline)
                    Text("Install a Windows program, or open the Steam tab and add your Steam games.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.apps) { app in
                            AppCard(app: app, onRemove: { toRemove = app })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .alert("Remove from the library?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } })) {
            Button("Remove", role: .destructive) { if let a = toRemove { model.remove(a) }; toRemove = nil }
            Button("Cancel", role: .cancel) { toRemove = nil }
        } message: {
            Text("It stays installed in its bottle; this only removes it from Burrow's list.")
        }
    }
}

struct AppCard: View {
    @EnvironmentObject var model: BurrowModel
    let app: LibraryApp
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: app.isSteamGame ? "gamecontroller.fill" : "app.fill")
                    .font(.title2).foregroundColor(.accentColor)
                Spacer()
                Menu {
                    Button("Play with compatible graphics") { model.launch(app, compat: true) }
                        .disabled(app.isSteamGame)
                    Button("Make a Dock shortcut") { model.makeShortcut(app) }
                    Divider()
                    Button("Remove from library", action: onRemove)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            Text(app.name).font(.headline).lineLimit(2)
            Text(app.isSteamGame ? "Steam" : "Bottle: \(app.bottle)").font(.caption).foregroundColor(.secondary)
            Button { model.launch(app) } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }
}

struct SteamView: View {
    @EnvironmentObject var model: BurrowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Windows Steam").font(.title2).bold()
                Spacer()
                if model.status.has("steam") {
                    Button { model.syncSteam() } label: { Label("Add Games to Library", systemImage: "square.and.arrow.down") }
                    Button { model.openSteam() } label: { Label("Open Steam", systemImage: "play.fill") }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if !model.status.has("setup") {
                Text("Set up Burrow first (Setup tab).").foregroundColor(.secondary)
                Spacer()
            } else if !model.status.has("steam") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Burrow downloads Steam's Windows installer from Valve and puts it in its own bottle. Then sign in and install games like you would on a PC.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.installSteam() } label: { Label("Install Windows Steam", systemImage: "arrow.down.circle") }
                        .controlSize(.large)
                }
                Spacer()
            } else {
                Text("Installed games").font(.headline)
                if model.games.isEmpty {
                    Text("No games yet. Open Steam, install some, then press Refresh.").foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(model.games) { game in
                        HStack {
                            Image(systemName: "gamecontroller")
                            Text(game.name)
                            Spacer()
                            Text(game.id).font(.caption).foregroundColor(.secondary)
                            Button("Play") { model.play(game) }
                        }
                        .padding(.vertical, 2)
                    }
                }
                HStack {
                    Button { model.refreshGames() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Spacer()
                    Text("If Steam's first start closes by itself, it was updating; press Open Steam again.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { model.refreshGames() }
    }
}

struct UsageView: View {
    @EnvironmentObject var model: BurrowModel
    @State private var confirmStopAll = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private struct BottleGroup: Identifiable {
        let id: String  // bottle name
        let rows: [ProcRow]
    }

    private var procsByBottle: [BottleGroup] {
        let groups = Dictionary(grouping: model.procs, by: { $0.bottle })
        return groups.keys.sorted().map { BottleGroup(id: $0, rows: groups[$0] ?? []) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Disk space").font(.headline)
                        Spacer()
                        if model.diskLoading { ProgressView().controlSize(.small) }
                        Button { model.refreshDisk() } label: { Image(systemName: "arrow.clockwise") }
                            .help("Measure again")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.disk) { row in
                                UsageBar(label: label(for: row), kb: row.kb, total: max(model.diskTotal, 1),
                                         indent: row.kind == "game")
                            }
                        }
                    }
                    Divider()
                    HStack { Text("Burrow uses").bold(); Spacer(); Text(humanKB(model.diskTotal)).bold() }
                    HStack {
                        Text("Free on this Mac")
                        Spacer()
                        Text(humanKB(model.diskFree))
                            .foregroundColor(model.diskFree < 20 * 1_048_576 ? Color.orange : Color.primary)
                    }
                    if model.diskFree > 0 && model.diskFree < 20 * 1_048_576 {
                        Text("Under 20 GB free: big games may not fit.").font(.caption).foregroundColor(.orange)
                    }
                    Button("Open Burrow's Folder") { model.openFolder() }
                }
                .padding(6)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Memory (RAM) in use").font(.headline)
                        Spacer()
                        Text(humanKB(model.procs.reduce(0) { $0 + $1.kb })).bold()
                    }
                    if model.procs.isEmpty {
                        Text("No Windows programs are running.").foregroundColor(.secondary)
                        Spacer()
                    } else {
                        List {
                            ForEach(procsByBottle) { group in
                                Section(header: HStack {
                                    Text(group.id)
                                    Spacer()
                                    Text(humanKB(group.rows.reduce(0) { $0 + $1.kb }))
                                    Button("Quit") { model.stopBottle(group.id) }.controlSize(.small)
                                }) {
                                    ForEach(group.rows) { p in
                                        HStack { Text(p.name); Spacer(); Text(humanKB(p.kb)).foregroundColor(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    Button(role: .destructive) { confirmStopAll = true } label: {
                        Label("Quit All Windows Programs", systemImage: "xmark.octagon")
                    }
                    .disabled(model.procs.isEmpty)
                }
                .padding(6)
            }
        }
        .onAppear { model.refreshDisk(); model.refreshMemory() }
        .onReceive(timer) { _ in model.refreshMemory() }
        .confirmationDialog("Quit every Windows program?", isPresented: $confirmStopAll) {
            Button("Quit All", role: .destructive) { model.stopAll() }
        } message: {
            Text("Unsaved progress in games and programs will be lost.")
        }
    }

    private func label(for row: DiskRow) -> String {
        switch row.kind {
        case "bottle": return "Bottle: \(row.name)"
        default: return row.name
        }
    }
}

struct UsageBar: View {
    let label: String
    let kb: Double
    let total: Double
    var indent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(indent ? .caption : .body)
                Spacer()
                Text(humanKB(kb)).font(indent ? .caption : .body).foregroundColor(.secondary)
            }
            ProgressView(value: min(kb / total, 1))
        }
        .padding(.leading, indent ? 16 : 0)
    }
}

struct SetupView: View {
    @EnvironmentObject var model: BurrowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Setup").font(.title2).bold()
                StepRow(done: model.status.has("setup"), title: "Wine and DXMT",
                        detail: "The open source Windows layer and the Direct3D-to-Metal graphics layer (about 300 MB).") {
                    Button("Download") { model.runJob("Downloading Wine and DXMT", ["setup"]) }
                }
                StepRow(done: model.status.has("clt"), title: "Apple Command Line Tools",
                        detail: "Free from Apple. Needed to build turbo graphics.") {
                    Button("Install") { model.runJob("Apple Command Line Tools", ["tools"]) }
                }
                StepRow(done: model.status.has("brew"), title: "Homebrew",
                        detail: "Free tool installer from brew.sh. It asks for your Mac password, so it opens in Terminal.") {
                    Button("Install in Terminal…") { model.installHomebrewInTerminal() }
                }
                StepRow(done: model.status.has("turbo"), title: "Turbo graphics",
                        detail: model.status.has("arm") || !model.status.has("mac")
                            ? "Builds fast Metal graphics that most 3D games need. One time, a few minutes."
                            : "Needs an Apple Silicon Mac.") {
                    Button("Build") { model.runJob("Building turbo graphics", ["turbo"]) }
                        .disabled(!model.status.has("setup") || !model.status.has("brew"))
                }
                StepRow(done: model.status.has("steam"), title: "Windows Steam",
                        detail: "Installs Steam from Valve into its own bottle.") {
                    Button("Install") { model.installSteam() }.disabled(!model.status.has("setup"))
                }
                StepRow(done: model.status.has("gst"), title: "GStreamer (optional)",
                        detail: "Lets game intro videos play. Get the macOS runtime installer.") {
                    Button("Open Download Page") {
                        NSWorkspace.shared.open(URL(string: "https://gstreamer.freedesktop.org/download/#macos")!)
                    }
                }
                Divider()
                HStack {
                    Button("Check Everything") { model.runJob("Checking everything", ["doctor"]) }
                    Button("Show Logs") { model.openFolder("logs") }
                    Button("Refresh") { model.refreshAll() }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct StepRow<Actions: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done { actions() }
        }
    }
}

struct Banner: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text)
            Spacer()
            Button(button, action: action)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

struct ConsoleView: View {
    @EnvironmentObject var model: BurrowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.consoleTitle).font(.headline)
                Spacer()
                if model.jobRunning { ProgressView().controlSize(.small) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.consoleText.isEmpty ? "Starting…" : model.consoleText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.consoleText) { _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.consoleText, forType: .string)
                }
                Spacer()
                if model.jobRunning { Text("You can close this; the job keeps going.").font(.caption).foregroundColor(.secondary) }
                Button(model.jobRunning ? "Hide" : "Close") { model.showConsole = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
    }
}
