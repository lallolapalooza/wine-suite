/* Throwaway probe: does CLSID_SWbemDateTime exist and do its conversions work?
 * Build: x86_64-w64-mingw32-gcc -o swbemdatetime_probe.exe swbemdatetime_probe.c -lole32 -loleaut32 -luuid
 */
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <objbase.h>
#include <oleauto.h>
#include <wbemdisp.h>
#include <stdio.h>

static void print_date(const WCHAR *label, DATE d)
{
    SYSTEMTIME st;
    if (VariantTimeToSystemTime(d, &st))
        printf("  %ls = %04u-%02u-%02u %02u:%02u:%02u.%03u (raw %.9f)\n", label,
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, d);
    else
        printf("  %ls = <VariantTimeToSystemTime failed> (raw %.9f)\n", label, d);
}

static void dump_value(ISWbemDateTime *dt, const WCHAR *label)
{
    BSTR v = NULL;
    HRESULT hr = ISWbemDateTime_get_Value(dt, &v);
    printf("  %ls: hr=%08lx value=%ls\n", label, (unsigned long)hr, v ? v : L"(null)");
    SysFreeString(v);
}

static void run_conversions(ISWbemDateTime *dt)
{
    BSTR v, ft;
    DATE d;
    VARIANT_BOOL b;
    LONG l;
    HRESULT hr;

    printf("-- normal timestamp (UTC) --\n");
    v = SysAllocString(L"20000120195632.000000+000");
    hr = ISWbemDateTime_put_Value(dt, v);
    SysFreeString(v);
    printf("  put_Value hr=%08lx\n", (unsigned long)hr);
    dump_value(dt, L"value");
    ISWbemDateTime_get_Year(dt, &l);       printf("  Year=%ld\n", l);
    ISWbemDateTime_get_Month(dt, &l);      printf("  Month=%ld\n", l);
    ISWbemDateTime_get_Day(dt, &l);        printf("  Day=%ld\n", l);
    ISWbemDateTime_get_Hours(dt, &l);      printf("  Hours=%ld\n", l);
    ISWbemDateTime_get_UTC(dt, &l);        printf("  UTC=%ld\n", l);
    d = 0;
    hr = ISWbemDateTime_GetVarDate(dt, VARIANT_FALSE, &d);
    printf("  GetVarDate(false) hr=%08lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) print_date(L"  -> date", d);
    ft = NULL;
    hr = ISWbemDateTime_GetFileTime(dt, VARIANT_FALSE, &ft);
    printf("  GetFileTime(false) hr=%08lx value=%ls\n", (unsigned long)hr, ft ? ft : L"(null)");
    SysFreeString(ft);

    printf("-- timestamp with -480 offset --\n");
    v = SysAllocString(L"20000120195632.000000-480");
    hr = ISWbemDateTime_put_Value(dt, v);
    SysFreeString(v);
    printf("  put_Value hr=%08lx\n", (unsigned long)hr);
    ISWbemDateTime_get_UTC(dt, &l);        printf("  UTC=%ld\n", l);
    d = 0;
    hr = ISWbemDateTime_GetVarDate(dt, VARIANT_FALSE, &d);
    printf("  GetVarDate(false) hr=%08lx (UTC instant)\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) print_date(L"  -> date", d);
    ft = NULL;
    hr = ISWbemDateTime_GetFileTime(dt, VARIANT_FALSE, &ft);
    printf("  GetFileTime(false) hr=%08lx value=%ls\n", (unsigned long)hr, ft ? ft : L"(null)");
    if (SUCCEEDED(hr))
    {
        BSTR ft2 = NULL;
        hr = ISWbemDateTime_SetFileTime(dt, ft, VARIANT_FALSE);
        printf("  SetFileTime(value,false) hr=%08lx\n", (unsigned long)hr);
        hr = ISWbemDateTime_GetFileTime(dt, VARIANT_FALSE, &ft2);
        printf("  GetFileTime again hr=%08lx value=%ls roundtrip=%ls\n", (unsigned long)hr,
               ft2 ? ft2 : L"(null)", (ft2 && !wcscmp(ft, ft2)) ? L"OK" : L"MISMATCH");
        SysFreeString(ft2);
    }
    SysFreeString(ft);

    printf("-- SetVarDate round trip --\n");
    {
        SYSTEMTIME st = { 2000, 1, 0, 20, 19, 56, 32, 0 };
        DATE in;
        SystemTimeToVariantTime(&st, &in);
        hr = ISWbemDateTime_SetVarDate(dt, in, VARIANT_FALSE);
        printf("  SetVarDate hr=%08lx\n", (unsigned long)hr);
        dump_value(dt, L"value");
    }

    printf("-- interval --\n");
    v = SysAllocString(L"00000100010003.000000:000");
    hr = ISWbemDateTime_put_Value(dt, v);
    SysFreeString(v);
    printf("  put_Value hr=%08lx\n", (unsigned long)hr);
    dump_value(dt, L"value");
    b = VARIANT_FALSE;
    ISWbemDateTime_get_IsInterval(dt, &b);
    printf("  IsInterval=%d\n", b);
    ISWbemDateTime_get_Day(dt, &l);        printf("  Day=%ld\n", l);
    ISWbemDateTime_get_Hours(dt, &l);      printf("  Hours=%ld\n", l);
    ISWbemDateTime_get_Seconds(dt, &l);    printf("  Seconds=%ld\n", l);
    d = 0;
    hr = ISWbemDateTime_GetVarDate(dt, VARIANT_FALSE, &d);
    printf("  GetVarDate(false) on interval hr=%08lx (expect 80041001)\n", (unsigned long)hr);

    printf("-- malformed --\n");
    v = SysAllocString(L"garbage");
    hr = ISWbemDateTime_put_Value(dt, v);
    SysFreeString(v);
    printf("  put_Value(\"garbage\") hr=%08lx (expect 80041021)\n", (unsigned long)hr);
    dump_value(dt, L"value unchanged?");
}

int main(void)
{
    ISWbemDateTime *dt = NULL;
    IUnknown *unk = NULL;
    HRESULT hr;

    CoInitialize(NULL);

    hr = CoCreateInstance(&CLSID_SWbemDateTime, NULL, CLSCTX_INPROC_SERVER,
                          &IID_ISWbemDateTime, (void **)&dt);
    printf("CoCreateInstance(CLSID_SWbemDateTime) -> %08lx %ls\n", (unsigned long)hr,
           hr == S_OK ? L"(S_OK)" : L"");

    if (dt)
    {
        hr = ISWbemDateTime_QueryInterface(dt, &IID_IDispatch, (void **)&unk);
        printf("QueryInterface(IID_IDispatch) -> %08lx\n", (unsigned long)hr);
        if (unk) IUnknown_Release(unk);
        run_conversions(dt);
        ISWbemDateTime_Release(dt);
    }

    CoUninitialize();
    return 0;
}
