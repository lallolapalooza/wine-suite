/* svcenum_probe.c -- dump exactly what EnumServicesStatusExA gives a caller,
 * so Wine's answer can be compared with Windows' for the same request CapCut makes:
 *   OpenSCManagerA(NULL,NULL,SC_MANAGER_ENUMERATE_SERVICE)
 *   EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
 *                         buf, size, &needed, &returned, &resume, NULL)
 *
 * build: x86_64-w64-mingw32-gcc -O2 -o svcenum_probe.exe svcenum_probe.c -ladvapi32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#define max(a,b) ((a)>(b)?(a):(b))

static void hexdump(const unsigned char *p, unsigned n, unsigned long base)
{
    unsigned i;
    for (i = 0; i < n; i += 16) {
        unsigned j;
        printf("  %08lx:", base + i);
        for (j = 0; j < 16; j++) {
            if (i + j < n) printf(" %02x", p[i + j]);
            else printf("   ");
        }
        printf("  |");
        for (j = 0; j < 16 && i + j < n; j++) {
            unsigned char c = p[i + j];
            printf("%c", (c >= 32 && c < 127) ? c : '.');
        }
        printf("|\n");
    }
}

int main(void)
{
    SC_HANDLE scm;
    DWORD needed = 0, returned = 0, resume = 0, err;
    BOOL ok;
    BYTE *buf;
    SIZE_T sz;
    DWORD i, off;

    printf("sizeof(ENUM_SERVICE_STATUS_PROCESSA)=%lu\n",
           (unsigned long)sizeof(ENUM_SERVICE_STATUS_PROCESSA));
    printf("sizeof(ENUM_SERVICE_STATUSA)=%lu\n",
           (unsigned long)sizeof(ENUM_SERVICE_STATUSA));
    printf("SC_ENUM_PROCESS_INFO=%d SERVICE_WIN32=0x%lx SERVICE_ACTIVE=%lu\n",
           (int)SC_ENUM_PROCESS_INFO, (unsigned long)SERVICE_WIN32, (unsigned long)SERVICE_ACTIVE);

    scm = OpenSCManagerA(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE);
    printf("OpenSCManagerA -> %p err=%lu\n", (void *)scm, (unsigned long)GetLastError());
    if (!scm) return 1;

    /* exactly CapCut's first call: buffer NULL, size 0 */
    needed = returned = resume = 0;
    SetLastError(0);
    ok = EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                               NULL, 0, &needed, &returned, &resume, NULL);
    err = GetLastError();
    printf("QUERY  ok=%d err=%lu needed=%lu returned=%lu resume=%lu\n",
           ok, (unsigned long)err, (unsigned long)needed,
           (unsigned long)returned, (unsigned long)resume);

    /* exactly CapCut's second call: a fresh zeroed buffer of 'needed' bytes.
     * CapCut passed size 0x4a0, so also print what a caller-sized buffer does. */
    sz = needed ? needed : 0x1000;
    buf = (BYTE *)malloc(sz + 0x100);
    if (!buf) return 2;
    /* fill with 0xAA so we can see exactly which bytes the API writes */
    memset(buf, 0xAA, sz + 0x100);

    needed = returned = resume = 0;
    SetLastError(0);
    ok = EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                               buf, (DWORD)sz, &needed, &returned, &resume, NULL);
    err = GetLastError();
    printf("FILL   sz=%lu ok=%d err=%lu needed=%lu returned=%lu resume=%lu\n",
           (unsigned long)sz, ok, (unsigned long)err, (unsigned long)needed,
           (unsigned long)returned, (unsigned long)resume);

    if (ok) {
        ENUM_SERVICE_STATUS_PROCESSA *arr = (ENUM_SERVICE_STATUS_PROCESSA *)buf;
        for (i = 0; i < returned && i < 12; i++)
            printf("  [%lu] %-24s | %-32s | type=%08lx state=%lu ctrl=%08lx pid=%lu\n",
                   (unsigned long)i,
                   arr[i].lpServiceName ? arr[i].lpServiceName : "(null)",
                   arr[i].lpDisplayName ? arr[i].lpDisplayName : "(null)",
                   (unsigned long)arr[i].ServiceStatusProcess.dwServiceType,
                   (unsigned long)arr[i].ServiceStatusProcess.dwCurrentState,
                   (unsigned long)arr[i].ServiceStatusProcess.dwControlsAccepted,
                   (unsigned long)arr[i].ServiceStatusProcess.dwProcessId);

        /* where do the strings actually live?  offsets relative to buf */
        off = returned * (DWORD)sizeof(ENUM_SERVICE_STATUS_PROCESSA);
        printf("array bytes=%lu (0x%lx); string pointer offsets:\n",
               (unsigned long)off, (unsigned long)off);
        {
            DWORD hi = 0, lo = 0xffffffff;
            for (i = 0; i < returned && i < 12; i++) {
                printf("  [%lu] name_off=%ld display_off=%ld\n",
                       (unsigned long)i,
                       (long)(arr[i].lpServiceName - (char *)buf),
                       arr[i].lpDisplayName ? (long)(arr[i].lpDisplayName - (char *)buf) : -1L);
            }
            for (i = 0; i < returned; i++) {
                if (arr[i].lpServiceName) {
                    DWORD o = (DWORD)(arr[i].lpServiceName - (char *)buf);
                    if (o < lo) lo = o;
                    o = (DWORD)(arr[i].lpServiceName + strlen(arr[i].lpServiceName) + 1 - (char *)buf);
                    if (o > hi) hi = o;
                }
                if (arr[i].lpDisplayName) {
                    DWORD o = (DWORD)(arr[i].lpDisplayName - (char *)buf);
                    if (o < lo) lo = o;
                    o = (DWORD)(arr[i].lpDisplayName + strlen(arr[i].lpDisplayName) + 1 - (char *)buf);
                    if (o > hi) hi = o;
                }
            }
            printf("string block = [%lu (0x%lx) .. %lu (0x%lx)]  [buffer sz=%lu]\n",
                   (unsigned long)lo, (unsigned long)lo, (unsigned long)hi, (unsigned long)hi, (unsigned long)sz);
        }
        /* the byte the overrunning loop lands on: entry[returned] */
        printf("entry[returned] at offset %lu (0x%lx):\n", (unsigned long)off, (unsigned long)off);
        hexdump(buf + off, 64, off);
        printf("  as qword: %016llx  as string: '%.*s'\n",
               (unsigned long long)*(unsigned long long *)(buf + off), 32, (char *)(buf + off));
        /* first 8-byte zero word at/after the entry array */
        for (i = off; i + 8 <= sz; i++)
            if (*(unsigned long long *)(buf + i) == 0) break;
        printf("  first zero qword at/after entries: offset %lu (0x%lx), %ld bytes past entries\n",
               (unsigned long)i, (unsigned long)i, (long)i - (long)off);
    } else {
        hexdump(buf, 64, 0);
    }
    CloseServiceHandle(scm);
    return 0;
}
