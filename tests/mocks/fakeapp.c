/* Test double: as "setup" it installs itself and makes a Start Menu shortcut; as the app
   it writes its command line and working folder to C:\burrow-test\ran.txt. */
#define COBJMACROS
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <objbase.h>
#include <stdio.h>
#include <wchar.h>

static void make_link(const wchar_t *target, const wchar_t *lnk)
{
    IShellLinkW *sl; IPersistFile *pf;
    CoInitialize(NULL);
    if (SUCCEEDED(CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, (void **)&sl))) {
        IShellLinkW_SetPath(sl, target);
        IShellLinkW_SetArguments(sl, L"--from-shortcut");
        wchar_t dir[MAX_PATH]; wcscpy(dir, target); *wcsrchr(dir, L'\\') = 0;
        IShellLinkW_SetWorkingDirectory(sl, dir);
        if (SUCCEEDED(IShellLinkW_QueryInterface(sl, &IID_IPersistFile, (void **)&pf))) {
            IPersistFile_Save(pf, lnk, TRUE);
            IPersistFile_Release(pf);
        }
        IShellLinkW_Release(sl);
    }
}

int wmain(int argc, wchar_t **argv)
{
    wchar_t self[MAX_PATH]; GetModuleFileNameW(NULL, self, MAX_PATH);
    if (argc > 1 && wcscmp(argv[1], L"--install") == 0 || wcsstr(self, L"setup")) {
        wchar_t dir[] = L"C:\\Program Files\\Fake App";
        CreateDirectoryW(dir, NULL);
        CopyFileW(self, L"C:\\Program Files\\Fake App\\Fake App.exe", FALSE);
        wchar_t menu[MAX_PATH]; SHGetFolderPathW(NULL, CSIDL_COMMON_PROGRAMS, NULL, 0, menu);
        wchar_t lnk[MAX_PATH]; swprintf(lnk, MAX_PATH, L"%ls\\Fake App.lnk", menu);
        make_link(L"C:\\Program Files\\Fake App\\Fake App.exe", lnk);
        swprintf(lnk, MAX_PATH, L"%ls\\Uninstall Fake App.lnk", menu);
        make_link(L"C:\\Program Files\\Fake App\\Fake App.exe", lnk);
        return 0;
    }
    CreateDirectoryW(L"C:\\burrow-test", NULL);
    FILE *f = _wfopen(L"C:\\burrow-test\\ran.txt", L"w");
    wchar_t cwd[MAX_PATH]; GetCurrentDirectoryW(MAX_PATH, cwd);
    fwprintf(f, L"cmd=%ls\ncwd=%ls\n", GetCommandLineW(), cwd);
    fclose(f);
    return 0;
}
