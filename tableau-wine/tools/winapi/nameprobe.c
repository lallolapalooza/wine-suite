/*
 * nameprobe.c - GetUserNameExW's contract for the extended-name formats, measured the same way on both
 * platforms so the two behaviours can be diffed instead of guessed (same method as tools/winapi/asimp.c,
 * roprobe.c, kprobe.c: raw return values plus GetLastError(), one line per call).
 *
 * Power BI Desktop's identity path calls this from `PlatformEmailProvider.TryGetPlatformEmail`
 * (`PBI.PQ.AcquirePlatformEmail` -> `Secur32Wrapper.GetUserName` -> secur32!GetUserNameExW), with the
 * two-call protocol: first with a NULL buffer and *nSize = 0 to learn the required size (expected:
 * FALSE + ERROR_MORE_DATA = 234), then with a buffer of that size.  The whole email lookup short-circuits
 * on the first call, so what that call leaves in the last error is the observable.
 *
 * Wine implemented only NameSamCompatible and answered ERROR_NONE_MAPPED (1332) for every other format.
 * The fix is expected to answer NameUserPrincipal (8) as "user@dns.domain" and NameDnsDomain (12) as
 * "dns.domain\user" from the machine's DNS domain - and, like Windows, to keep answering
 * ERROR_NONE_MAPPED when the machine has no DNS domain to build either from.  This probe prints the
 * inputs to that decision (the Tcpip\Parameters\Domain registry value and GetComputerNameExW) as well:
 *
 *   GetComputerNameExW(DnsDomain) ...
 *   GetUserNameExW( 8 NameUserPrincipal ) sizing NULL/0    ret=0 lastError=234 nSize=22
 *   GetUserNameExW( 8 NameUserPrincipal ) call   buf/22    ret=1 lastError=0   nSize=21 name="user@corp.example.com"
 *   GetUserNameExW( 8 NameUserPrincipal ) short  buf/1     ret=0 lastError=234 nSize=22
 *
 * Formats 0 (NameUnknown / invalid) and every format Wine answers NONE_MAPPED for are included so the
 * shape of the answer (which formats have an answer, and what the error is when they do not) is visible,
 * not just the one case.
 *
 * Everything is resolved with LoadLibrary/GetProcAddress: the same binary must run on Windows (reference)
 * and under Wine (our implementation), and the interesting datum is which module answered with what.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o bin/nameprobe.exe nameprobe.c -ladvapi32
 * usage: nameprobe.exe [logfile]
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>

/* EXTENDED_NAME_FORMAT, spelled out with the documented values so the printed number is unambiguous. */
#define FMT_NAME_UNKNOWN              0
#define FMT_NAME_FULLY_QUALIFIED_DN   1
#define FMT_NAME_SAM_COMPATIBLE       2
#define FMT_NAME_DISPLAY              3
#define FMT_NAME_UNIQUE_ID            6
#define FMT_NAME_CANONICAL            7
#define FMT_NAME_USER_PRINCIPAL       8
#define FMT_NAME_CANONICAL_EX         9
#define FMT_NAME_SERVICE_PRINCIPAL   10
#define FMT_NAME_DNS_DOMAIN          12

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

typedef BOOL (WINAPI *pGetUserNameExW)(int, LPWSTR, PULONG);
typedef BOOL (WINAPI *pGetComputerNameExW)(int, LPWSTR, LPDWORD);

static FILE *g_log;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    if (g_log) vfprintf(g_log, fmt, ap);
    va_end(ap);
    fflush(stdout);
    if (g_log) fflush(g_log);
}

/* One GetUserNameExW call: value = this call's return, then GetLastError() and the in/out size, read
 * before anything else can disturb them. */
static void call_row(pGetUserNameExW fn, const char *what, int format, const char *name,
                     LPWSTR buf, ULONG buf_len)
{
    ULONG size = buf_len;
    BOOL ok;
    DWORD err;
    BOOL printed_name = 0;

    if (buf && buf_len) buf[0] = 0;   /* visible as empty when the call does not fill it */
    SetLastError(0);
    ok = fn(format, buf, &size);
    err = GetLastError();
    if (ok && buf)
    {
        say("GetUserNameExW(%2d %-16s) %-7s %-9s ret=%d lastError=%-4lu nSize=%-3lu name=\"%ls\"\n",
            format, name, what, buf ? "buf" : "NULL", ok, (unsigned long)err, (unsigned long)size, buf);
        printed_name = 1;
    }
    if (!printed_name)
        say("GetUserNameExW(%2d %-16s) %-7s %-9s ret=%d lastError=%-4lu nSize=%-3lu\n",
            format, name, what, buf ? "buf" : "NULL", ok, (unsigned long)err, (unsigned long)size);
}

/* Read a REG_SZ value or die trying; returns 0 when absent/empty (and says so). */
static void print_reg_sz(const char *label, const WCHAR *subkey, const WCHAR *value)
{
    HKEY key;
    WCHAR data[512];
    DWORD size = sizeof(data), type = 0;
    LONG ret;

    if ((ret = RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey, 0, KEY_READ, &key)))
    {
        say("%-28s <no key: %ld>\n", label, (long)ret);
        return;
    }
    ret = RegQueryValueExW(key, value, NULL, &type, (BYTE *)data, &size);
    RegCloseKey(key);
    if (ret) say("%-28s <no value: %ld>\n", label, (long)ret);
    else     say("%-28s type=%lu value=\"%ls\"\n", label, (unsigned long)type, data);
}

int main(int argc, char **argv)
{
    static const struct { int format; const char *name; } formats[] = {
        { FMT_NAME_SAM_COMPATIBLE,     "NameSamCompatible"  },
        { FMT_NAME_DISPLAY,            "NameDisplay"        },
        { FMT_NAME_UNIQUE_ID,          "NameUniqueId"       },
        { FMT_NAME_CANONICAL,          "NameCanonical"      },
        { FMT_NAME_USER_PRINCIPAL,     "NameUserPrincipal"  },
        { FMT_NAME_CANONICAL_EX,       "NameCanonicalEx"    },
        { FMT_NAME_SERVICE_PRINCIPAL,  "NameServicePrincipal" },
        { FMT_NAME_DNS_DOMAIN,         "NameDnsDomain"      },
    };
    HMODULE secur32 = LoadLibraryW(L"secur32.dll");
    HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    pGetUserNameExW fn = secur32 ? (void *)GetProcAddress(secur32, "GetUserNameExW") : NULL;
    pGetComputerNameExW gcne = (void *)GetProcAddress(k32, "GetComputerNameExW");
    WCHAR buf[512], user[256];
    DWORD len;
    unsigned i;

    if (argc > 1) g_log = fopen(argv[1], "w");
    setvbuf(stdout, NULL, _IONBF, 0);

    say("GetUserNameExW contract (value = the call's return; lastError read immediately after it)\n");
    say("secur32.dll=%p GetUserNameExW=%p kernel32!GetComputerNameExW=%p\n",
        (void *)secur32, (void *)fn, (void *)gcne);

    /* The inputs the NameUserPrincipal/NameDnsDomain answers are built from. */
    print_reg_sz("Domain (Tcpip\\Parameters)", L"System\\CurrentControlSet\\Services\\Tcpip\\Parameters", L"Domain");
    print_reg_sz("Hostname (Tcpip\\Parameters)", L"System\\CurrentControlSet\\Services\\Tcpip\\Parameters", L"Hostname");
    if (gcne)
    {
        BOOL ok;
        DWORD err;

        /* 2 = ComputerNameDnsDomain, 3 = ComputerNameDnsFullyQualified - the inputs the new answers use */
        len = ARRAY_SIZE(buf); buf[0] = 0;
        SetLastError(0);
        ok = gcne(2, buf, &len);
        err = GetLastError();
        say("GetComputerNameExW(2 DnsDomain)         ret=%d lastError=%-4lu len=%-3lu name=\"%ls\"\n",
            ok, (unsigned long)err, (unsigned long)len, buf);

        len = ARRAY_SIZE(buf); buf[0] = 0;
        SetLastError(0);
        ok = gcne(3, buf, &len);
        err = GetLastError();
        say("GetComputerNameExW(3 DnsFullyQualified) ret=%d lastError=%-4lu len=%-3lu name=\"%ls\"\n",
            ok, (unsigned long)err, (unsigned long)len, buf);
    }
    {
        BOOL ok;
        DWORD err;

        len = ARRAY_SIZE(user); user[0] = 0;
        SetLastError(0);
        ok = GetUserNameW(user, &len);
        err = GetLastError();
        say("GetUserNameW                            ret=%d lastError=%-4lu name=\"%ls\"\n",
            ok, (unsigned long)err, user);
    }

    if (!fn)
    {
        say("no secur32!GetUserNameExW - nothing to measure\n");
        return 2;
    }

    say("\n");
    for (i = 0; i < ARRAY_SIZE(formats); i++)
    {
        ULONG need = 0;

        /* the sizing call the application makes: NULL buffer, *nSize = 0 */
        SetLastError(0);
        {
            ULONG size = 0;
            BOOL ok = fn(formats[i].format, NULL, &size);
            DWORD err = GetLastError();
            say("GetUserNameExW(%2d %-16s) %-7s %-9s ret=%d lastError=%-4lu nSize=%-3lu\n",
                formats[i].format, formats[i].name, "sizing", "NULL", ok, (unsigned long)err,
                (unsigned long)size);
            need = size;
        }

        /* the sized call: exactly what the sizing call asked for (256 is a safe fallback) */
        if (need == 0 || need > ARRAY_SIZE(buf)) need = ARRAY_SIZE(buf);
        call_row(fn, "call", formats[i].format, formats[i].name, buf, need);

        /* and a deliberately too-small buffer: the truncation contract the patch has to match */
        call_row(fn, "short", formats[i].format, formats[i].name, buf, 1);

        say("\n");
    }
    say("done\n");
    if (g_log) fclose(g_log);
    return 0;
}
