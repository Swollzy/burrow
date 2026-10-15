/*
 * Burrow's steamwebhelper wrapper (MIT).
 *
 * Steam's window is a Chromium browser (steamwebhelper.exe). Under Wine on a
 * Mac its GPU process paints the window black and its separate network
 * process fails TLS handshakes, so Steam opens to a black or "no connection"
 * window. Running Chromium with CPU drawing in a single process avoids both.
 * The fix and its reasoning come from steam-on-m1-wine (MIT, notpop); this is
 * a fresh implementation of the same idea.
 *
 * Burrow renames Valve's file to steamwebhelper_real.exe and puts this one in
 * its place. Every start runs:
 *     "<this folder>\steamwebhelper_real.exe" --disable-gpu --single-process <original args>
 * and returns the child's exit code.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -municode -mwindows -static -o steamwebhelper.exe steamwebhelper-wrapper.c
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

/* Burrow greps the .exe for this to tell its wrapper from Valve's file. */
const char burrow_marker[] = "BURROW-WEBHELPER-WRAPPER-1";

#define EXTRA_FLAGS L"--disable-gpu --single-process"
#define REAL_NAME   L"steamwebhelper_real.exe"

/* Skips the program name at the start of a command line, quoted or not. */
static const wchar_t *skip_program_name(const wchar_t *p)
{
    if (*p == L'"') {
        p++;
        while (*p && *p != L'"') p++;
        if (*p == L'"') p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t') p++;
    }
    while (*p == L' ' || *p == L'\t') p++;
    return p;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmdline, int show)
{
    (void)inst; (void)prev; (void)cmdline; (void)show;
    volatile const char *keep = burrow_marker; (void)keep;

    wchar_t self[32768];
    DWORD len = GetModuleFileNameW(NULL, self, sizeof(self) / sizeof(self[0]));
    if (len == 0 || len >= sizeof(self) / sizeof(self[0])) return 1;
    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return 1;
    slash[1] = L'\0';

    const wchar_t *args = skip_program_name(GetCommandLineW());
    size_t need = wcslen(self) + wcslen(REAL_NAME) + wcslen(EXTRA_FLAGS) + wcslen(args) + 8;
    wchar_t *real = (wchar_t *)calloc(wcslen(self) + wcslen(REAL_NAME) + 1, sizeof(wchar_t));
    wchar_t *line = (wchar_t *)calloc(need, sizeof(wchar_t));
    if (!real || !line) return 1;

    wcscpy(real, self);
    wcscat(real, REAL_NAME);
    /* "<real>" <flags> <args> */
    wcscpy(line, L"\"");
    wcscat(line, real);
    wcscat(line, L"\" " EXTRA_FLAGS);
    if (*args) {
        wcscat(line, L" ");
        wcscat(line, args);
    }

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessW(real, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return (int)GetLastError();

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)code;
}
