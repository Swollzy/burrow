/* Test double for Steam.exe: logs its arguments, then starts bin\cef\cef.win64\steamwebhelper.exe
   with a sample argument the way Steam does. */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
int wmain(void)
{
    CreateDirectoryW(L"C:\\burrow-test", NULL);
    FILE *f = _wfopen(L"C:\\burrow-test\\steam.txt", L"a");
    fwprintf(f, L"%ls\n", GetCommandLineW()); fclose(f);
    wchar_t line[] = L"\"C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win64\\steamwebhelper.exe\" -lang=en_US --type=browser";
    STARTUPINFOW si = { sizeof(si) }; PROCESS_INFORMATION pi;
    if (CreateProcessW(NULL, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, 10000);
        CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    }
    return 0;
}
