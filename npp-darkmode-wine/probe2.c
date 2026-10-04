#include <windows.h>
#include <uxtheme.h>
#include <vsstyle.h>
#include <vssym32.h>
#include <stdio.h>

typedef HRESULT (WINAPI *fnDrawThemeTextEx)(HTHEME,HDC,int,int,LPCWSTR,int,DWORD,LPRECT,const DTTOPTS*);
typedef BOOL (WINAPI *fnIsThemeActive)(void);
typedef BOOL (WINAPI *fnIsAppThemed)(void);

int main(void)
{
    HMODULE ux = LoadLibraryW(L"uxtheme.dll");
    fnIsThemeActive isActive = (fnIsThemeActive)GetProcAddress(ux, "IsThemeActive");
    fnIsAppThemed  isApp    = (fnIsAppThemed)GetProcAddress(ux, "IsAppThemed");
    printf("IsThemeActive=%d IsAppThemed=%d\n", isActive ? isActive() : -1, isApp ? isApp() : -1);

    HWND hwnd = GetDesktopWindow();
    static const wchar_t *classes[] = { L"Menu", L"DarkMode_Explorer::Menu", L"Explorer::Menu",
                                        L"DarkMode_Explorer", L"Explorer", L"DarkMode_Explorer::ScrollBar" };
    for (int i = 0; i < 6; i++)
    {
        SetLastError(0xdeadbeef);
        HTHEME ht = OpenThemeData(hwnd, classes[i]);
        printf("OpenThemeData(%ls) = %p (err %lu)\n", classes[i], (void*)ht, GetLastError());
        if (ht)
        {
            HDC dc = GetDC(NULL);
            RECT rc = {0,0,60,20};
            HRESULT hr = DrawThemeBackground(ht, dc, MENU_BARITEM, MBI_NORMAL, &rc, NULL);
            DTTOPTS to = { sizeof(to) }; to.dwFlags = DTT_TEXTCOLOR; to.crText = 0xffffff;
            fnDrawThemeTextEx dte = (fnDrawThemeTextEx)GetProcAddress(ux, "DrawThemeTextEx");
            HRESULT hr2 = dte ? dte(ht, dc, MENU_BARITEM, MBI_NORMAL, L"File", 4, DT_CENTER|DT_SINGLELINE|DT_VCENTER, &rc, &to) : E_FAIL;
            printf("   DrawThemeBackground(MENU_BARITEM/NORMAL)=0x%08lx DrawThemeTextEx=%p hr=0x%08lx\n",
                   (unsigned long)hr, (void*)dte, (unsigned long)hr2);
            ReleaseDC(NULL, dc);
            CloseThemeData(ht);
        }
    }
    return 0;
}
