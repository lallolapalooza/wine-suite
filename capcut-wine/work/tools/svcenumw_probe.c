/* svcenumw_probe.c -- same layout characterisation for EnumServicesStatusExW.
 * build: x86_64-w64-mingw32-gcc -O2 -o svcenumw_probe.exe svcenumw_probe.c -ladvapi32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    SC_HANDLE scm = OpenSCManagerA(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE);
    DWORD qn = 0, qr = 0, resume = 0, i, lo = ~0u, hi = 0, off, sz, aa;
    BYTE *buf;
    ENUM_SERVICE_STATUS_PROCESSW *arr;

    if (!scm) return 1;
    EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                          NULL, 0, &qn, &qr, &resume, NULL);
    printf("query needed=%lu err=%lu\n", (unsigned long)qn, (unsigned long)GetLastError());
    sz = qn;
    buf = malloc(sz);
    memset(buf, 0xAA, sz);
    SetLastError(0);
    if (!EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                               buf, sz, &qn, &qr, &resume, NULL)) {
        printf("fill failed %lu\n", (unsigned long)GetLastError());
        return 1;
    }
    arr = (ENUM_SERVICE_STATUS_PROCESSW *)buf;
    for (i = 0; i < qr; i++) {
        DWORD o;
        if (arr[i].lpServiceName) {
            o = (DWORD)((char *)arr[i].lpServiceName - (char *)buf); if (o < lo) lo = o;
            o += (DWORD)(wcslen(arr[i].lpServiceName) + 1) * 2; if (o > hi) hi = o;
        }
        if (arr[i].lpDisplayName) {
            o = (DWORD)((char *)arr[i].lpDisplayName - (char *)buf); if (o < lo) lo = o;
            o += (DWORD)(wcslen(arr[i].lpDisplayName) + 1) * 2; if (o > hi) hi = o;
        }
    }
    off = qr * (DWORD)sizeof(ENUM_SERVICE_STATUS_PROCESSW);
    printf("size=%lu returned=%lu array=[0..%lu] strings=[%lu..%lu] tail=%lu\n",
           (unsigned long)sz, (unsigned long)qr, (unsigned long)off,
           (unsigned long)lo, (unsigned long)hi, (unsigned long)(sz - hi));
    aa = 0; for (i = off; i < lo && i < sz; i++) if (buf[i] == 0xAA) aa++;
    printf("0xAA in gap = %lu of %lu\n", (unsigned long)aa, (unsigned long)(lo - off));
    printf("entry[0] name@%ld disp@%ld ; entry[ret-1] name@%ld disp@%ld\n",
           (long)((char *)arr[0].lpServiceName - (char *)buf),
           (long)((char *)arr[0].lpDisplayName - (char *)buf),
           (long)((char *)arr[qr - 1].lpServiceName - (char *)buf),
           (long)((char *)arr[qr - 1].lpDisplayName - (char *)buf));
    printf("bytes at entry[ret] (off %lu): %02x %02x %02x %02x %02x %02x %02x %02x\n",
           (unsigned long)off, buf[off], buf[off+1], buf[off+2], buf[off+3],
           buf[off+4], buf[off+5], buf[off+6], buf[off+7]);
    printf("first string: %ls\n", arr[qr - 1].lpDisplayName ? arr[qr - 1].lpDisplayName : L"(null)");
    CloseServiceHandle(scm);
    return 0;
}
