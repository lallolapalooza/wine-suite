/* memtext.c — read a target process's memory and print printable strings containing markers.
 *
 * Why: Resolume Arena's log is buffered in-process and lost on kill, so the log file can lag by
 * minutes (or never flush). The log text is still in the process's heap; scanning the committed
 * private memory for lines containing "INFO:" shows how far the app really is.
 *
 * usage: memtext.exe <marker> [--pid N | --name Arena.exe] [--all]
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o memtext.exe memtext.c -lpsapi
 */
#include <windows.h>
#include <psapi.h>
#include <stdio.h>
#include <string.h>

static DWORD find_pid(const char *name)
{
    DWORD pids[2048], needed = 0, i;
    if (!EnumProcesses(pids, sizeof pids, &needed)) return 0;
    for (i = 0; i < needed / sizeof(DWORD); i++) {
        HANDLE h;
        char base[MAX_PATH] = "";
        if (!pids[i]) continue;
        h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pids[i]);
        if (!h) continue;
        if (GetModuleBaseNameA(h, NULL, base, sizeof base) && !_stricmp(base, name)) {
            CloseHandle(h);
            return pids[i];
        }
        CloseHandle(h);
    }
    return 0;
}

int main(int argc, char **argv)
{
    const char *marker;
    const char *name = "Arena.exe";
    DWORD pid = 0;
    HANDLE h;
    HMODULE mods[1024];
    DWORD needed = 0;
    unsigned char *base = NULL, *p, *end;
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("usage: memtext.exe <marker> [--pid N|--name X]\n"); return 2; }
    marker = argv[1];
    for (i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--pid") && i + 1 < argc) pid = (DWORD)strtoul(argv[++i], NULL, 10);
        else if (!strcmp(argv[i], "--name") && i + 1 < argc) name = argv[++i];
    }
    if (!pid) pid = find_pid(name);
    if (!pid) { printf("process '%s' not found\n", name); return 1; }
    printf("pid=%lu marker=\"%s\"\n", pid, marker);

    h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!h) { printf("OpenProcess failed %lu\n", GetLastError()); return 1; }
    if (EnumProcessModules(h, mods, sizeof mods, &needed))
        base = (unsigned char *)(uintptr_t)mods[0];
    (void)base;

    {
        MEMORY_BASIC_INFORMATION mbi;
        unsigned char *addr = NULL;
        char buf[65536];
        SIZE_T got;
        int found = 0;
        while (VirtualQueryEx(h, addr, &mbi, sizeof mbi)) {
            unsigned char *region = (unsigned char *)mbi.BaseAddress;
            SIZE_T size = mbi.RegionSize;
            addr = region + size;
            if (mbi.State != MEM_COMMIT) continue;
            if (mbi.Type != MEM_PRIVATE && mbi.Type != MEM_MAPPED) continue;
            if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) continue;
            if (!(mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                                 PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
                continue;
            if (size > 64u * 1024u * 1024u) size = 64u * 1024u * 1024u;
            {
                SIZE_T off = 0;
                while (off < size) {
                    SIZE_T chunk = size - off > sizeof buf ? sizeof buf : size - off;
                    if (!ReadProcessMemory(h, region + off, buf, chunk, &got)) break;
                    for (SIZE_T k = 0; k + strlen(marker) < got; k++) {
                        if (!memcmp(buf + k, marker, strlen(marker))) {
                            /* walk back to line start */
                            SIZE_T s = k;
                            while (s > 0 && buf[s - 1] != '\n') s--;
                            /* print up to the next newline */
                            SIZE_T e = k;
                            while (e < got && buf[e] != '\n' && e - s < 300) e++;
                            fwrite(buf + s, 1, e - s, stdout);
                            putchar('\n');
                            found++;
                            k = e;
                        }
                    }
                    off += chunk;
                }
            }
        }
        printf("(matches=%d)\n", found);
    }
    CloseHandle(h);
    return 0;
}
