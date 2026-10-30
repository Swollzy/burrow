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

struct BottleInfo: Identifiable, Hashable {
    let id: String  // the bottle's name
    let graphics: String
    let windows: String
    let preset: String
    let desktop: String
}

/// One row of `burrow settings … --plain`.
struct SettingItem: Identifiable, Hashable {
    let id: String  // key
    var value: String  // for an app, "" means "same as its bottle"
    let inherited: String  // the value that applies when nothing is set here
    let type: String  // bool, int, choice, text
    let choices: [String]
    let defaultValue: String
    let detail: String
}

struct SnapshotInfo: Identifiable, Hashable {
    let id: String
    let label: String
    let created: String
}

struct ComponentInfo: Identifiable, Hashable {
    let id: String  // winetricks name
    let installed: Bool
    let detail: String
}

struct PresetInfo: Identifiable, Hashable {
    let id: String
    let detail: String
}

/// Whose settings a settings sheet edits: a bottle, or one app in it.
struct SettingsTarget: Hashable {
    var bottle: String
    var appID: String? = nil
    var appName: String? = nil
    var cliArgs: [String] { appID.map { ["settings", "--app", $0] } ?? ["settings", bottle] }
    var title: String { appName.map { "Settings for \($0)" } ?? "Settings for bottle “\(bottle)”" }
}

enum ActiveSheet: Identifiable {
    case install(URL, String?)  // installer, bottle to preselect
    case newBottle
    case settings(SettingsTarget)
    case snapshots(String)
    case components(String)

    var id: String {
        switch self {
        case .install(let url, _): return "install:" + url.path
        case .newBottle: return "new-bottle"
        case .settings(let t): return "settings:\(t.bottle):\(t.appID ?? "")"
        case .snapshots(let b): return "snapshots:" + b
        case .components(let b): return "components:" + b
        }
    }
}

func tabRows(_ out: String) -> [[String]] {
    out.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
}

/// Friendlier names for setting keys and values.
func settingTitle(_ key: String) -> String {
    switch key {
    case "graphics": return "Graphics"
    case "windows_version": return "Windows version"
    case "virtual_desktop": return "Windows desktop window"
    case "retina": return "Retina resolution"
    case "dpi": return "Scale (DPI)"
    case "option_as_alt": return "Option key is Alt"
    case "command_as_ctrl": return "Command key is Ctrl"
    case "fullscreen_capture": return "Fullscreen takes over the display"
    case "msync": return "Fast syncing (msync)"
    case "cpu_cores": return "CPU core limit"
    case "hud": return "Performance HUD"
    case "wine_debug": return "Logging"
    case "dll_overrides": return "DLL overrides"
    case "env": return "Environment variables"
    case "args": return "Launch options"
    default: return key
    }
}

func choiceTitle(_ value: String) -> String {
    switch value {
    case "auto": return "Auto"
    case "turbo": return "Turbo (Metal)"
    case "compat": return "Compatible (OpenGL)"
    case "win11": return "Windows 11"
    case "win10": return "Windows 10"
    case "win81": return "Windows 8.1"
    case "win8": return "Windows 8"
    case "win7": return "Windows 7"
    case "vista": return "Windows Vista"
    case "winxp64": return "Windows XP"
    case "off": return "Off"
    case "errors": return "Errors"
    case "verbose": return "Verbose"
    default: return value
    }
}

func humanKB(_ kb: Double) -> String {
    if kb >= 1_048_576 { return String(format: "%.1f GB", kb / 1_048_576) }
    if kb >= 1024 { return String(format: "%.0f MB", kb / 1024) }
    return String(format: "%.0f KB", kb)
}

// MARK: - Model

final class BurrowModel: ObservableObject {
    /// One model for the whole app, so the app delegate can hand it files opened from Finder.
    static let shared = BurrowModel()

    @Published var status = BurrowStatus()
    @Published var apps: [LibraryApp] = []
    @Published var bottles: [BottleInfo] = []
    @Published var presets: [PresetInfo] = []
    @Published var activeSheet: ActiveSheet?
    @Published var alertText: String?
    private var autoSetupTried = false
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

    private init() {
        let env = ProcessInfo.processInfo.environment
        home = env["BURROW_HOME"] ?? (NSHomeDirectory() + "/Library/Application Support/Burrow")
        if env["BURROW_CLI"] == nil { BurrowModel.installBundledCLI(into: home + "/app") }
        cli = env["BURROW_CLI"] ?? (home + "/app/bin/burrow")
        refreshAll()
    }

    /// The DMG build carries the burrow tool inside the app (Contents/Resources/burrow-cli).
    /// Copy it to where install.sh puts it, so shortcuts and `burrow` in Terminal keep working
    /// when the app is moved or replaced. Only copies when the bundled tool is different.
    static func installBundledCLI(into dest: String) {
        let fm = FileManager.default
        guard let res = Bundle.main.resourcePath else { return }
        let bundled = res + "/burrow-cli"
        guard let fresh = fm.contents(atPath: bundled + "/bin/burrow") else { return }
        if fm.contents(atPath: dest + "/bin/burrow") == fresh { return }
        let staging = dest + ".new"
        do {
            try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            try? fm.removeItem(atPath: staging)
            try fm.copyItem(atPath: bundled, toPath: staging)
            try? fm.removeItem(atPath: dest)
            try fm.moveItem(atPath: staging, toPath: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest + "/bin/burrow")
        } catch {
            NSLog("Burrow: couldn't install the bundled tool: \(error)")
            return
        }
        // Copies of a downloaded app keep its quarantine flag; clear it the way install.sh does.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", dest]
        do { try xattr.run(); xattr.waitUntilExit() } catch {}
        // Like install.sh, let `burrow` work in Terminal; leave an existing link alone.
        let bin = NSHomeDirectory() + "/.local/bin"
        if (try? fm.destinationOfSymbolicLink(atPath: bin + "/burrow")) == nil {
            try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try? fm.createSymbolicLink(atPath: bin + "/burrow", withDestinationPath: dest + "/bin/burrow")
        }
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

    /// Runs a command and hands back its exit status and everything it printed, errors included.
    func run(_ args: [String], done: @escaping (Int32, String) -> Void) {
        guard cliExists else { done(1, "Burrow's command-line tool is missing at \(cli). Reopen Burrow from Applications, or run install.sh again."); return }
        let p = makeProcess(args)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        DispatchQueue.global(qos: .userInitiated).async {
            var text = ""
            var code: Int32 = 1
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                text = String(decoding: data, as: UTF8.self)
                code = p.terminationStatus
            } catch {
                text = error.localizedDescription
            }
            DispatchQueue.main.async { done(code, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    /// Like `run`, but shows what went wrong in an alert.
    func runOrAlert(_ args: [String], then: (() -> Void)? = nil) {
        run(args) { [weak self] code, out in
            if code != 0 { self?.alertText = out.isEmpty ? "That didn't work." : out }
            then?()
        }
    }

    /// Closes the open sheet first, then does something that may open another sheet
    /// (macOS shows one at a time).
    func afterSheet(_ action: @escaping () -> Void) {
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    func present(_ sheet: ActiveSheet) {
        if showConsole {
            showConsole = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.activeSheet = sheet }
        } else if activeSheet != nil {
            afterSheet { [weak self] in self?.activeSheet = sheet }
        } else {
            activeSheet = sheet
        }
    }

    /// Starts something that keeps running on its own (a game, Steam). Output goes to Burrow's logs,
    /// but if burrow itself stops with an error ("Turbo graphics isn't built", "no app called…"),
    /// that's shown instead of nothing happening.
    func fire(_ args: [String]) {
        guard cliExists else { alertText = "Burrow's command-line tool is missing at \(cli). Reopen Burrow from Applications, or run install.sh again."; return }
        let p = makeProcess(args)
        p.standardOutput = FileHandle.nullDevice
        // Errors go to a temporary file, not a pipe: the game or Steam inherit it and outlive
        // burrow, and writing to a pipe nobody reads any more would kill them.
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let errHandle = try? FileHandle(forWritingTo: errURL)
        p.standardError = errHandle ?? FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            try? errHandle?.close()
            let text = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: errURL)
            guard proc.terminationStatus != 0 else { return }
            let errors = text.split(separator: "\n").filter { $0.contains("error:") }.map(String.init)
            guard !errors.isEmpty else { return }
            DispatchQueue.main.async { self?.alertText = errors.joined(separator: "\n") }
        }
        do {
            try p.run()
        } catch {
            try? errHandle?.close()
            try? FileManager.default.removeItem(at: errURL)
            alertText = "Couldn't start burrow: \(error.localizedDescription)"
        }
    }

    /// Reads what's already in a pipe without waiting for its writers to close it: Wine processes
    /// that outlive burrow (wineserver, Steam) can hold it open for a long time.
    static func drainNow(_ handle: FileHandle) -> Data {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return data
    }

    /// Jobs asked for while another one runs (an install dropped on the window during setup)
    /// wait their turn instead of being dropped.
    private var queuedJobs: [(title: String, args: [String], then: (() -> Void)?)] = []

    /// Runs a long job and streams its output into the console sheet.
    func runJob(_ title: String, _ args: [String], then: (() -> Void)? = nil) {
        if jobRunning {
            queuedJobs.append((title: title, args: args, then: then))
            consoleText += "\n⏳ \(title) starts when this finishes."
            showConsole = true
            return
        }
        startJob(title, args, then: then, keepText: false)
    }

    private func startNextJob(afterFailure failed: Bool) {
        guard !jobRunning, !queuedJobs.isEmpty else { return }
        if failed {
            consoleText += "\n\nSkipped because of the error above: " + queuedJobs.map { $0.title }.joined(separator: ", ")
            queuedJobs.removeAll()
            return
        }
        let next = queuedJobs.removeFirst()
        startJob(next.title, next.args, then: next.then, keepText: true)
    }

    private func startJob(_ title: String, _ args: [String], then: (() -> Void)?, keepText: Bool) {
        consoleTitle = title
        consoleText = keepText ? consoleText + "\n\n── \(title) ──\n" : ""
        lastJobFailed = false
        jobRunning = true
        showConsole = true
        guard cliExists else {
            consoleText = "Burrow's command-line tool is missing at:\n\(cli)\nReopen Burrow from Applications, or run install.sh again."
            jobRunning = false
            lastJobFailed = true
            startNextJob(afterFailure: true)
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
            let rest = BurrowModel.drainNow(pipe.fileHandleForReading)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !rest.isEmpty { self.consoleText += String(decoding: rest, as: UTF8.self) }
                self.jobRunning = false
                self.lastJobFailed = proc.terminationStatus != 0
                self.consoleText += self.lastJobFailed
                    ? "\n✗ Stopped with an error. Use Copy to include this when reporting a problem."
                    : "\n✓ Done."
                self.refreshAll()
                let failed = self.lastJobFailed
                if !failed { then?() }
                self.startNextJob(afterFailure: failed)
            }
        }
        do {
            try p.run()
        } catch {
            consoleText += "\nCouldn't start burrow: \(error.localizedDescription)"
            jobRunning = false
            lastJobFailed = true
            startNextJob(afterFailure: true)
        }
    }

    // MARK: Refreshing

    func refreshAll() {
        refreshStatus()
        refreshApps()
        refreshBottles()
        refreshPresets()
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
            self?.autoSetupIfNeeded()
        }
    }

    /// The first time Burrow opens it sets itself up (downloads Wine and DXMT) without being asked.
    private func autoSetupIfNeeded() {
        guard !autoSetupTried, status.loaded, status.has("mac"), !status.has("setup"), !jobRunning, cliExists else { return }
        autoSetupTried = true
        runJob("Setting up Burrow", ["setup"])
    }

    func refreshBottles() {
        capture(["bottle", "list", "--plain"]) { [weak self] out in
            self?.bottles = tabRows(out).compactMap { f -> BottleInfo? in
                guard f.count >= 5, !f[0].isEmpty else { return nil }
                return BottleInfo(id: f[0], graphics: f[1], windows: f[2], preset: f[3], desktop: f[4])
            }.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
    }

    func refreshPresets() {
        capture(["presets", "--plain"]) { [weak self] out in
            self?.presets = tabRows(out).compactMap { f -> PresetInfo? in
                guard f.count >= 2 else { return nil }
                return PresetInfo(id: f[0], detail: f[1])
            }
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

    private func pickWindowsFile(_ title: String, types: [String] = ["exe", "msi"]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Picks an installer, then asks which bottle it goes in.
    func installProgram(into bottle: String? = nil) {
        guard let url = pickWindowsFile("Pick a Windows installer") else { return }
        present(.install(url, bottle))
    }

    /// Files dropped on the window or opened from Finder with Burrow.
    func openFiles(_ urls: [URL]) {
        guard let url = urls.first(where: { ["exe", "msi"].contains($0.pathExtension.lowercased()) }) else { return }
        present(.install(url, nil))
    }

    func install(_ url: URL, bottle: String, preset: String) {
        var args = ["install", url.path, "--bottle", bottle]
        if !preset.isEmpty { args += ["--preset", preset] }
        runJob("Installing \(url.lastPathComponent)", args)
    }

    /// Runs a program once without installing it (portable programs, tools, patches).
    func runProgram(in bottle: String) {
        guard let url = pickWindowsFile("Pick a Windows program to run", types: ["exe", "msi", "bat"]) else { return }
        fire(["run", bottle, url.path])
    }

    /// Puts a program that's already on the Mac (a portable app) in the library.
    func addProgram(in bottle: String) {
        guard let url = pickWindowsFile("Pick a Windows program", types: ["exe"]) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        runOrAlert(["add", name, "--bottle", bottle, "--exe", url.path]) { [weak self] in self?.refreshApps() }
    }

    func newBottle(_ name: String, preset: String) {
        var args = ["bottle", "new", name]
        if !preset.isEmpty { args += ["--preset", preset] }
        runJob("Creating bottle \(name)", args)
    }

    func duplicateBottle(_ bottle: String) {
        var name = "\(bottle) copy"
        var n = 2
        while bottles.contains(where: { $0.id == name }) { name = "\(bottle) copy \(n)"; n += 1 }
        runJob("Copying bottle \(bottle)", ["bottle", "clone", bottle, name])
    }

    func deleteBottle(_ bottle: String) {
        runOrAlert(["bottle", "delete", bottle, "--yes"]) { [weak self] in
            self?.refreshBottles()
            self?.refreshApps()
        }
    }

    func openDesktop(_ bottle: String) { fire(["desktop", bottle]) }

    func wineSettings(_ bottle: String) { fire(["winecfg", bottle]) }

    func openDrive(_ bottle: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: home + "/bottles/" + bottle + "/prefix/drive_c"))
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

/// Hands .exe and .msi files opened from Finder ("Open With > Burrow") to the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async { BurrowModel.shared.openFiles(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BurrowModel.shared

    var body: some Scene {
        WindowGroup("Burrow") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 840, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Windows Program…") { model.installProgram() }
                    .keyboardShortcut("o")
                Button("New Bottle…") { model.present(.newBottle) }
                    .keyboardShortcut("n")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: BurrowModel
    @State private var tab = 0
    @State private var choseStartTab = false

    private let setupTab = 4

    var body: some View {
        VStack {
            TabView(selection: $tab) {
                LibraryView(goToSetup: { tab = setupTab })
                    .tabItem { Label("Library", systemImage: "square.grid.2x2") }.tag(0)
                BottlesView()
                    .tabItem { Label("Bottles", systemImage: "shippingbox") }.tag(1)
                SteamView()
                    .tabItem { Label("Steam", systemImage: "gamecontroller") }.tag(2)
                UsageView()
                    .tabItem { Label("Usage", systemImage: "internaldrive") }.tag(3)
                SetupView()
                    .tabItem { Label("Setup", systemImage: "wrench.and.screwdriver") }.tag(setupTab)
            }
            .padding()
            .sheet(isPresented: $model.showConsole) { ConsoleView().environmentObject(model) }
        }
        .sheet(item: $model.activeSheet) { sheet in
            Group {
                switch sheet {
                case .install(let url, let bottle): InstallSheet(url: url, preselected: bottle)
                case .newBottle: NewBottleSheet()
                case .settings(let target): SettingsSheet(target: target)
                case .snapshots(let bottle): SnapshotsSheet(bottle: bottle)
                case .components(let bottle): ComponentsSheet(bottle: bottle)
                }
            }
            .environmentObject(model)
        }
        .alert("Burrow", isPresented: Binding(get: { model.alertText != nil }, set: { if !$0 { model.alertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertText ?? "")
        }
        // Drop a Windows installer anywhere on the window to install it.
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async { model.openFiles([url]) }
            }
            return true
        }
        // The status arrives a moment after launch; open on Setup until Wine is installed.
        .onReceive(model.$status) { status in
            guard status.loaded, !choseStartTab else { return }
            choseStartTab = true
            if !status.has("setup") { tab = setupTab }
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
                    Text("Install a Windows program (or drop its installer here), or open the Steam tab and add your Steam games.")
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
                    Button("Settings…") {
                        model.present(.settings(SettingsTarget(bottle: app.bottle, appID: app.id, appName: app.name)))
                    }
                    .disabled(app.isSteamGame)
                    Button("Bottle Settings…") { model.present(.settings(SettingsTarget(bottle: app.bottle))) }
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
                        detail: "Free from Apple. Needed to build turbo graphics and this window.") {
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
                        .disabled(!model.status.has("setup") || !model.status.has("clt") || !model.status.has("brew"))
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

// MARK: - Bottles

struct BottlesView: View {
    @EnvironmentObject var model: BurrowModel
    @State private var toDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bottles").font(.title2).bold()
                Spacer()
                Button { model.refreshBottles() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Button { model.present(.newBottle) } label: { Label("New Bottle…", systemImage: "plus") }
                    .disabled(!model.status.has("setup"))
            }
            Text("Each bottle is its own lightweight Windows install, like a small VM that opens in seconds. Give it its own settings, save a snapshot before a risky change, or open it as a whole Windows desktop.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.bottles.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("No bottles yet.").font(.headline)
                    Text("Installing a program makes one, or press New Bottle.").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.bottles) { bottle in
                            BottleRow(bottle: bottle, onDelete: { toDelete = bottle.id })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { model.refreshBottles() }
        .alert("Delete this bottle?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete", role: .destructive) { if let b = toDelete { model.deleteBottle(b) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: {
            Text("Everything installed in “\(toDelete ?? "")” and all its snapshots will be deleted. This can't be undone.")
        }
    }
}

struct BottleRow: View {
    @EnvironmentObject var model: BurrowModel
    let bottle: BottleInfo
    var onDelete: () -> Void

    private var summary: String {
        var parts = [choiceTitle(bottle.windows), "graphics: " + choiceTitle(bottle.graphics).lowercased()]
        if bottle.desktop != "off" { parts.append("desktop window \(bottle.desktop)") }
        if !bottle.preset.isEmpty { parts.append(bottle.preset.capitalized + " preset") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").font(.title).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.id).font(.headline)
                Text(summary).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button { model.openDesktop(bottle.id) } label: { Label("Windows Desktop", systemImage: "macwindow") }
                .help("Open this bottle as a whole Windows desktop in one window")
            Button { model.present(.settings(SettingsTarget(bottle: bottle.id))) } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            Menu {
                Button("Install Windows Program…") { model.installProgram(into: bottle.id) }
                Button("Run a Program Once (.exe)…") { model.runProgram(in: bottle.id) }
                Button("Add a Program to the Library (.exe)…") { model.addProgram(in: bottle.id) }
                Divider()
                Button("Snapshots…") { model.present(.snapshots(bottle.id)) }
                Button("Windows Components…") { model.present(.components(bottle.id)) }
                Button("Duplicate Bottle") { model.duplicateBottle(bottle.id) }
                Divider()
                Button("Show C: Drive in Finder") { model.openDrive(bottle.id) }
                Button("Wine Settings (winecfg)") { model.wineSettings(bottle.id) }
                Button("Quit Its Programs") { model.stopBottle(bottle.id) }
                Divider()
                Button("Delete Bottle…", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }
}

/// Bottle names become folder names; keep them simple.
func bottleNameProblem(_ name: String) -> String? {
    let n = name.trimmingCharacters(in: .whitespaces)
    if n.isEmpty { return "Give the bottle a name." }
    if n.contains("/") || n.hasPrefix(".") || n.contains("\t") { return "Bottle names can't contain / or start with a dot." }
    return nil
}

struct PresetPicker: View {
    @EnvironmentObject var model: BurrowModel
    @Binding var preset: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Preset", selection: $preset) {
                Text("Standard").tag("")
                ForEach(model.presets) { p in Text(p.id.capitalized).tag(p.id) }
            }
            Text(model.presets.first(where: { $0.id == preset })?.detail
                 ?? "Windows 10 with Burrow's usual settings. You can change any of them later.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NewBottleSheet: View {
    @EnvironmentObject var model: BurrowModel
    @State private var name = ""
    @State private var preset = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Bottle").font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text("Games, Office, Old Games…"))
                PresetPicker(preset: $preset)
            }
            if let problem = bottleNameProblem(name), !name.isEmpty {
                Text(problem).font(.caption).foregroundColor(.red)
            } else if model.bottles.contains(where: { $0.id == name.trimmingCharacters(in: .whitespaces) }) {
                Text("There's already a bottle with that name.").font(.caption).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.activeSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    let p = preset
                    model.afterSheet { model.newBottle(n, preset: p) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bottleNameProblem(name) != nil
                          || model.bottles.contains(where: { $0.id == name.trimmingCharacters(in: .whitespaces) }))
            }
        }
        .padding()
        .frame(width: 520)
    }
}

struct InstallSheet: View {
    @EnvironmentObject var model: BurrowModel
    let url: URL
    let preselected: String?
    @State private var intoNew = true
    @State private var newName = ""
    @State private var existing = ""
    @State private var preset = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install \(url.lastPathComponent)").font(.headline)
            Form {
                Picker("Install into", selection: $intoNew) {
                    Text("A new bottle").tag(true)
                    Text("An existing bottle").tag(false).disabled(model.bottles.isEmpty)
                }
                .pickerStyle(.radioGroup)
                if intoNew {
                    TextField("Bottle name", text: $newName)
                    PresetPicker(preset: $preset)
                } else {
                    Picker("Bottle", selection: $existing) {
                        ForEach(model.bottles) { b in Text(b.id).tag(b.id) }
                    }
                }
            }
            Text("Each bottle is a separate Windows install. Programs that work together, like a game and its mods or an app and its plug-ins, should share one.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.status.has("setup") {
                Text("Burrow is still setting up; installing waits until Wine is downloaded.")
                    .font(.caption).foregroundColor(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.activeSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Install") {
                    let bottle = intoNew ? newName.trimmingCharacters(in: .whitespaces) : existing
                    let p = intoNew ? preset : ""
                    let file = url
                    model.afterSheet { model.install(file, bottle: bottle, preset: p) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(intoNew ? bottleNameProblem(newName) != nil : existing.isEmpty)
            }
        }
        .padding()
        .frame(width: 560)
        .onAppear {
            newName = url.deletingPathExtension().lastPathComponent
            if let b = preselected, model.bottles.contains(where: { $0.id == b }) {
                intoNew = false
                existing = b
            } else {
                existing = model.bottles.first?.id ?? ""
            }
        }
    }
}

// MARK: - Settings

struct SettingRow: View {
    @Binding var item: SettingItem
    /// An app's settings: "" means "same as the bottle".
    let inherits: Bool

    private var inheritedLabel: String {
        let v = item.inherited.isEmpty ? "none" : (item.type == "choice" ? choiceTitle(item.inherited) : item.inherited)
        return "Same as bottle (\(v))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch item.type {
            case "bool":
                if inherits {
                    Picker(settingTitle(item.id), selection: $item.value) {
                        Text(inheritedLabel).tag("")
                        Text("On").tag("on")
                        Text("Off").tag("off")
                    }
                } else {
                    Toggle(settingTitle(item.id), isOn: Binding(get: { item.value == "on" },
                                                                set: { item.value = $0 ? "on" : "off" }))
                }
            case "choice":
                Picker(settingTitle(item.id), selection: $item.value) {
                    if inherits { Text(inheritedLabel).tag("") }
                    ForEach(item.choices, id: \.self) { c in Text(choiceTitle(c)).tag(c) }
                }
            default:
                TextField(settingTitle(item.id), text: $item.value,
                          prompt: Text(inherits ? inheritedLabel : (item.defaultValue.isEmpty ? "none" : item.defaultValue)))
            }
            Text(item.detail)
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var model: BurrowModel
    let target: SettingsTarget
    @State private var items: [SettingItem] = []
    @State private var original: [String: String] = [:]
    @State private var loading = true
    @State private var busy = false
    @State private var message = ""
    @State private var failed = false
    @State private var preset = ""

    private var isApp: Bool { target.appID != nil }

    /// "key=value" for everything changed; an emptied value goes back to the default.
    private var changes: [String] {
        items.filter { original[$0.id] != $0.value }
            .map { "\($0.id)=\($0.value.isEmpty ? "default" : $0.value)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.title).font(.headline)
            if isApp {
                Text("Anything left on “Same as bottle” follows the settings of the bottle “\(target.bottle)”.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                HStack(alignment: .top) {
                    PresetPicker(preset: $preset).frame(maxWidth: 360)
                    Button("Apply Preset") { applyPreset() }.disabled(preset.isEmpty || busy)
                    Spacer()
                }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    ForEach($items) { $item in SettingRow(item: $item, inherits: isApp) }
                }
                .formStyle(.grouped)
            }
            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundColor(failed ? .red : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text("Changes apply the next time the bottle's programs start.").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { model.activeSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || loading || changes.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 600)
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        model.capture(target.cliArgs + ["--plain"]) { out in
            items = tabRows(out).compactMap { f -> SettingItem? in
                guard f.count >= 8 else { return nil }
                // An app shows only what it sets itself; the rest reads "Same as bottle".
                let value = (isApp && f[2] != "app") ? "" : f[1]
                return SettingItem(id: f[0], value: value, inherited: f[1], type: f[3],
                                   choices: f[4].split(separator: " ").map(String.init),
                                   defaultValue: f[5], detail: f[7])
            }
            original = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.value) })
            loading = false
        }
    }

    private func save() {
        busy = true
        model.run(target.cliArgs + changes) { code, out in
            busy = false
            if code == 0 {
                model.refreshBottles()
                model.activeSheet = nil
            } else {
                failed = true
                message = out
            }
        }
    }

    private func applyPreset() {
        busy = true
        model.run(["settings", target.bottle, "preset", preset]) { code, out in
            busy = false
            failed = code != 0
            message = code == 0 ? "Applied the \(preset.capitalized) preset." : out
            model.refreshBottles()
            load()
        }
    }
}

// MARK: - Snapshots

struct SnapshotsSheet: View {
    @EnvironmentObject var model: BurrowModel
    let bottle: String
    @State private var snapshots: [SnapshotInfo] = []
    @State private var label = ""
    @State private var busy = false
    @State private var message = ""
    @State private var needsForce = false
    @State private var toRestore: SnapshotInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snapshots of “\(bottle)”").font(.headline)
            Text("A snapshot saves the whole bottle as it is now. Make one before installing mods, updates or anything risky, and roll back if it goes wrong. On a Mac they take seconds and almost no space until the bottle changes.")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Label", text: $label, prompt: Text("Before installing mods"))
                Button("Take Snapshot") { save(force: false) }.disabled(busy)
                if needsForce { Button("Quit Programs and Save") { save(force: true) }.disabled(busy) }
            }
            if snapshots.isEmpty {
                Text("No snapshots yet.").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(snapshots) { s in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        VStack(alignment: .leading) {
                            Text(s.label)
                            Text(s.created).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Restore") { toRestore = s }.disabled(busy)
                        Button(role: .destructive) { delete(s) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .disabled(busy)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !message.isEmpty {
                Text(message).font(.callout).foregroundColor(.secondary).textSelection(.enabled)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { model.activeSheet = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 440)
        .onAppear(perform: load)
        .confirmationDialog("Roll “\(bottle)” back to this snapshot?",
                            isPresented: Binding(get: { toRestore != nil }, set: { if !$0 { toRestore = nil } })) {
            Button("Restore", role: .destructive) { if let s = toRestore { restore(s) }; toRestore = nil }
        } message: {
            Text("Its programs are closed, and everything changed in the bottle since “\(toRestore?.label ?? "")” is lost.")
        }
    }

    private func load() {
        model.capture(["snapshot", "list", bottle, "--plain"]) { out in
            snapshots = tabRows(out).compactMap { f -> SnapshotInfo? in
                guard f.count >= 3 else { return nil }
                return SnapshotInfo(id: f[0], label: f[1], created: f[2])
            }.sorted { $0.id > $1.id }
        }
    }

    private func save(force: Bool) {
        busy = true
        var args = ["snapshot", "save", bottle, label.isEmpty ? "Snapshot" : label]
        if force { args.append("--force") }
        model.run(args) { code, out in
            busy = false
            needsForce = code != 0 && out.contains("running")
            message = code == 0 ? "Saved." : out
            if code == 0 { label = "" }
            load()
        }
    }

    private func restore(_ s: SnapshotInfo) {
        busy = true
        model.run(["snapshot", "restore", bottle, s.id]) { code, out in
            busy = false
            message = code == 0 ? "Rolled back to “\(s.label)”." : out
            model.refreshAll()
        }
    }

    private func delete(_ s: SnapshotInfo) {
        busy = true
        model.run(["snapshot", "delete", bottle, s.id]) { code, out in
            busy = false
            message = code == 0 ? "" : out
            load()
        }
    }
}

// MARK: - Windows components

struct ComponentsSheet: View {
    @EnvironmentObject var model: BurrowModel
    let bottle: String
    @State private var items: [ComponentInfo] = []
    @State private var selected: Set<String> = []
    @State private var other = ""

    private var toInstall: [String] {
        let extra = other.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        return Array(selected).sorted() + extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windows components for “\(bottle)”").font(.headline)
            Text("Some programs need pieces of Windows that Wine doesn't include, like Microsoft's Visual C++ runtimes, .NET or fonts. Burrow installs them with winetricks. Tip: take a snapshot first.")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(items) { c in
                Toggle(isOn: Binding(get: { c.installed || selected.contains(c.id) },
                                     set: { on in if on { selected.insert(c.id) } else { selected.remove(c.id) } })) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.id).font(.system(.body, design: .monospaced))
                            Text(c.detail).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if c.installed { Text("Installed").font(.caption).foregroundColor(.green) }
                    }
                }
                .disabled(c.installed)
            }
            TextField("Other winetricks names", text: $other, prompt: Text("e.g. dotnet6 vcrun2005"))
            HStack {
                Spacer()
                Button("Cancel") { model.activeSheet = nil }.keyboardShortcut(.cancelAction)
                Button("Install") {
                    let names = toInstall
                    model.afterSheet {
                        model.runJob("Installing \(names.joined(separator: ", ")) into \(bottle)",
                                     ["components", bottle, "install"] + names)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(toInstall.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            model.capture(["components", bottle, "list", "--plain"]) { out in
                items = tabRows(out).compactMap { f -> ComponentInfo? in
                    guard f.count >= 3 else { return nil }
                    return ComponentInfo(id: f[0], installed: f[1] == "1", detail: f[2])
                }
            }
        }
    }
}
