/* svcenum_probe3.c -- characterise EnumServicesStatusExA's buffer layout exactly.
 * build: x86_64-w64-mingw32-gcc -O2 -o svcenum_probe3.exe svcenum_probe3.c -ladvapi32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    SC_HANDLE scm = OpenSCManagerA(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE);
    DWORD needed = 0, returned = 0, resume = 0, i, lo = ~0u, hi = 0, off, aa;
    BYTE *buf;
    ENUM_SERVICE_STATUS_PROCESSA *arr;

    if (!scm) return 1;
    EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                          NULL, 0, &needed, &returned, &resume, NULL);
    printf("query needed=%lu\n", (unsigned long)needed);
    buf = malloc(needed);
    memset(buf, 0xAA, needed);
    SetLastError(0);
    if (!EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                               buf, needed, &needed, &returned, &resume, NULL)) {
        printf("fill failed %lu\n", (unsigned long)GetLastError());
        return 1;
    }
    arr = (ENUM_SERVICE_STATUS_PROCESSA *)buf;
    for (i = 0; i < returned; i++) {
        DWORD o;
        if (arr[i].lpServiceName) {
            o = (DWORD)(arr[i].lpServiceName - (char *)buf); if (o < lo) lo = o;
            o += (DWORD)strlen(arr[i].lpServiceName) + 1; if (o > hi) hi = o;
        }
        if (arr[i].lpDisplayName) {
            o = (DWORD)(arr[i].lpDisplayName - (char *)buf); if (o < lo) lo = o;
            o += (DWORD)strlen(arr[i].lpDisplayName) + 1; if (o > hi) hi = o;
        }
    }
    off = returned * (DWORD)sizeof(ENUM_SERVICE_STATUS_PROCESSA);
    printf("size=%lu returned=%lu array=[0..%lu] strings=[%lu..%lu]\n",
           (unsigned long)needed, (unsigned long)returned, (unsigned long)off,
           (unsigned long)lo, (unsigned long)hi);
    aa = 0; for (i = off; i < lo; i++) if (buf[i] == 0xAA) aa++;
    printf("0xAA bytes in gap [array_end..strings) = %lu of %lu\n",
           (unsigned long)aa, (unsigned long)(lo - off));
    aa = 0; for (i = hi; i < needed; i++) if (buf[i] == 0xAA) aa++;
    printf("0xAA bytes in tail [strings_end..size) = %lu of %lu\n",
           (unsigned long)aa, (unsigned long)(needed - hi));
    aa = 0; for (i = 0; i < off; i++) if (buf[i] == 0xAA) aa++;
    printf("0xAA bytes inside array = %lu of %lu\n", (unsigned long)aa, (unsigned long)off);
    /* print the string block, in memory order, as NUL-terminated runs */
    printf("--- string block, memory order (off: text) ---\n");
    i = lo;
    while (i < hi) {
        if (buf[i]) {
            printf("  %5lu: %s\n", (unsigned long)i, (char *)(buf + i));
            i += (DWORD)strlen((char *)(buf + i)) + 1;
        } else { printf("  %5lu: <00>\n", (unsigned long)i); i++; }
    }
    printf("--- first 6 and last 3 entries' pointer offsets ---\n");
    for (i = 0; i < returned && i < 6; i++)
        printf("  [%lu] name@%ld disp@%ld\n", (unsigned long)i,
               (long)(arr[i].lpServiceName - (char *)buf),
               (long)(arr[i].lpDisplayName - (char *)buf));
    for (i = returned > 3 ? returned - 3 : 0; i < returned; i++)
        printf("  [%lu] name@%ld disp@%ld\n", (unsigned long)i,
               (long)(arr[i].lpServiceName - (char *)buf),
               (long)(arr[i].lpDisplayName - (char *)buf));
    CloseServiceHandle(scm);
    return 0;
}
