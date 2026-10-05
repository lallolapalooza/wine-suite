#include <windows.h>
#include <stdio.h>

typedef void (WINAPI *fnRtlGetNtVersionNumbers)(LPDWORD,LPDWORD,LPDWORD);

int main(void)
{
    DWORD data = 0xdeadbeef, size = sizeof(data);
    LSTATUS rc = RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &data, &size);
    printf("RegGetValueW(AppsUseLightTheme) rc=%ld value=%lu  -> isDarkModeReg=%d\n",
           (long)rc, (unsigned long)data, (rc == ERROR_SUCCESS && data == 0));

    HIGHCONTRASTW hc = { sizeof(hc) };
    BOOL ok = SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(hc), &hc, 0);
    printf("SPI_GETHIGHCONTRAST ok=%d flags=0x%lx -> IsHighContrast=%d\n",
           ok, (unsigned long)hc.dwFlags, (hc.dwFlags & HCF_HIGHCONTRASTON) ? 1 : 0);

    DWORD maj = 0, min = 0, bld = 0;
    fnRtlGetNtVersionNumbers f = (fnRtlGetNtVersionNumbers)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),
                                                                         "RtlGetNtVersionNumbers");
    if (f) { f(&maj, &min, &bld); bld &= ~0xF0000000u;
             printf("version %lu.%lu build %lu -> isWindows10=%d\n", (unsigned long)maj,
                    (unsigned long)min, (unsigned long)bld, bld >= 17763); }
    return 0;
}
