/* Test double for Valve's steamwebhelper.exe: logs the command line it was given. */
#include <windows.h>
#include <stdio.h>
int wmain(void)
{
    CreateDirectoryW(L"C:\\burrow-test", NULL);
    FILE *f = _wfopen(L"C:\\burrow-test\\helper.txt", L"a");
    fwprintf(f, L"%ls\n", GetCommandLineW()); fclose(f);
    return 0;
}
