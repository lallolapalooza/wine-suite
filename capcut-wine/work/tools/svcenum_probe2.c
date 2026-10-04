/* svcenum_probe2.c -- where does EnumServicesStatusExA put the strings, and does
 * that depend on the caller's buffer size?  Determines the rule to reproduce.
 * build: x86_64-w64-mingw32-gcc -O2 -o svcenum_probe2.exe svcenum_probe2.c -ladvapi32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static void one(SC_HANDLE scm, DWORD sz)
{
    BYTE *buf = malloc(sz);
    DWORD needed = 0, returned = 0, resume = 0, i, lo = 0xffffffff, hi = 0, off;
    ENUM_SERVICE_STATUS_PROCESSA *arr;
    BOOL ok;

    memset(buf, 0xAA, sz);
    SetLastError(0);
    ok = EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                               buf, sz, &needed, &returned, &resume, NULL);
    printf("== size=%lu ok=%d err=%lu returned=%lu ==\n", (unsigned long)sz, ok,
           (unsigned long)GetLastError(), (unsigned long)returned);
    if (!ok) { free(buf); return; }
    arr = (ENUM_SERVICE_STATUS_PROCESSA *)buf;
    for (i = 0; i < returned; i++) {
        if (arr[i].lpServiceName) {
            DWORD o = (DWORD)(arr[i].lpServiceName - (char *)buf);
            if (o < lo) lo = o;
            o += (DWORD)strlen(arr[i].lpServiceName) + 1;
            if (o > hi) hi = o;
        }
        if (arr[i].lpDisplayName) {
            DWORD o = (DWORD)(arr[i].lpDisplayName - (char *)buf);
            if (o < lo) lo = o;
            o += (DWORD)strlen(arr[i].lpDisplayName) + 1;
            if (o > hi) hi = o;
        }
    }
    off = returned * (DWORD)sizeof(ENUM_SERVICE_STATUS_PROCESSA);
    printf("array=[0..%lu] strings=[%lu(0x%lx)..%lu(0x%lx)] buffer=%lu\n",
           (unsigned long)off, (unsigned long)lo, (unsigned long)lo,
           (unsigned long)hi, (unsigned long)hi, (unsigned long)sz);
    printf("   entry[0].name_off=%ld entry[ret-1].name_off=%ld\n",
           (long)(arr[0].lpServiceName - (char *)buf),
           (long)(arr[returned - 1].lpServiceName - (char *)buf));
    printf("   bytes at entry[ret] (off %lu): %02x %02x %02x %02x %02x %02x %02x %02x\n",
           (unsigned long)off, buf[off], buf[off+1], buf[off+2], buf[off+3],
           buf[off+4], buf[off+5], buf[off+6], buf[off+7]);
    free(buf);
}

int main(void)
{
    SC_HANDLE scm = OpenSCManagerA(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE);
    DWORD needed = 0, returned = 0, resume = 0;
    if (!scm) { printf("OpenSCManager failed %lu\n", (unsigned long)GetLastError()); return 1; }
    EnumServicesStatusExA(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_ACTIVE,
                          NULL, 0, &needed, &returned, &resume, NULL);
    printf("query: needed=%lu returned=%lu err=%lu\n",
           (unsigned long)needed, (unsigned long)returned, (unsigned long)GetLastError());
    one(scm, needed);
    one(scm, needed + 0x200);
    one(scm, needed + 0x2000);
    CloseServiceHandle(scm);
    return 0;
}
