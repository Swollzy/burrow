/* Test double for Valve's SteamSetup.exe: checks it was run silently (/S), then puts a copy of
   itself where Steam.exe goes. */
#include <windows.h>
#include <wchar.h>
int wmain(int argc, wchar_t **argv)
{
    if (argc < 2 || wcscmp(argv[1], L"/S") != 0) return 2;
    wchar_t self[MAX_PATH];
    GetModuleFileNameW(NULL, self, MAX_PATH);
    CreateDirectoryW(L"C:\\Program Files (x86)\\Steam", NULL);
    return CopyFileW(self, L"C:\\Program Files (x86)\\Steam\\steam.exe", FALSE) ? 0 : 1;
}
