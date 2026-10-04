// Volume/path probe for the "Project saved path not found" modal.
//
// CapCut shows that modal while the directory exists and its config path matches Windows, so the failing
// check is something else — its own wording points at a volume probe on the drive the path resolves to.
// This prints exactly the calls such a check would make, so the same binary can be run under Wine and on
// the Windows guest and the two outputs diffed.
//
// build: x86_64-w64-mingw32-g++ -O1 -o volprobe.exe volprobe.c -static-libgcc -static-libstdc++
// run  : wine volprobe.exe "C:\\users\\asdf\\AppData\\Local\\CapCut\\User Data\\Projects"
#include <windows.h>
#include <cstdio>
#include <cstring>

static void dump_flags(DWORD flags)
{
    static const struct { DWORD bit; const char *name; } bits[] = {
        { FILE_CASE_SENSITIVE_SEARCH, "CASE_SENSITIVE_SEARCH" },
        { FILE_CASE_PRESERVED_NAMES, "CASE_PRESERVED_NAMES" },
        { FILE_UNICODE_ON_DISK, "UNICODE_ON_DISK" },
        { FILE_PERSISTENT_ACLS, "PERSISTENT_ACLS" },
        { FILE_FILE_COMPRESSION, "FILE_COMPRESSION" },
        { FILE_VOLUME_QUOTAS, "VOLUME_QUOTAS" },
        { FILE_SUPPORTS_SPARSE_FILES, "SUPPORTS_SPARSE_FILES" },
        { FILE_SUPPORTS_REPARSE_POINTS, "SUPPORTS_REPARSE_POINTS" },
        { FILE_SUPPORTS_REMOTE_STORAGE, "SUPPORTS_REMOTE_STORAGE" },
        { FILE_VOLUME_IS_COMPRESSED, "VOLUME_IS_COMPRESSED" },
        { FILE_SUPPORTS_OBJECT_IDS, "SUPPORTS_OBJECT_IDS" },
        { FILE_SUPPORTS_ENCRYPTION, "SUPPORTS_ENCRYPTION" },
        { FILE_NAMED_STREAMS, "NAMED_STREAMS" },
        { FILE_READ_ONLY_VOLUME, "READ_ONLY_VOLUME" },
        { FILE_SEQUENTIAL_WRITE_ONCE, "SEQUENTIAL_WRITE_ONCE" },
        { FILE_SUPPORTS_TRANSACTIONS, "SUPPORTS_TRANSACTIONS" },
        { FILE_SUPPORTS_HARD_LINKS, "SUPPORTS_HARD_LINKS" },
        { FILE_SUPPORTS_EXTENDED_ATTRIBUTES, "SUPPORTS_EXTENDED_ATTRIBUTES" },
        { FILE_SUPPORTS_OPEN_BY_FILE_ID, "SUPPORTS_OPEN_BY_FILE_ID" },
        { FILE_SUPPORTS_USN_JOURNAL, "SUPPORTS_USN_JOURNAL" },
        { FILE_SUPPORTS_INTEGRITY_STREAMS, "SUPPORTS_INTEGRITY_STREAMS" },
        { FILE_SUPPORTS_BLOCK_REFCOUNTING, "SUPPORTS_BLOCK_REFCOUNTING" },
        { FILE_SUPPORTS_SPARSE_VDL, "SUPPORTS_SPARSE_VDL" },
        { FILE_DAX_VOLUME, "DAX_VOLUME" },
        { FILE_SUPPORTS_GHOSTING, "SUPPORTS_GHOSTING" },
    };
    DWORD seen = 0;
    unsigned int i;

    printf("  flags decode   :");
    for (i = 0; i < sizeof(bits) / sizeof(bits[0]); i++)
        if (flags & bits[i].bit) { printf(" %s", bits[i].name); seen |= bits[i].bit; }
    if (flags & ~seen) printf(" unknown(%08lx)", flags & ~seen);
    printf("\n");
}

static void dump_drive(const wchar_t *path)
{
    wchar_t root[8] = {0};
    if (path[1] == L':') { root[0] = path[0]; root[1] = L':'; root[2] = L'\\'; root[3] = 0; }
    printf("path            : %ls\n", path);
    printf("root            : %ls\n", root);

    UINT dt = GetDriveTypeW(root);
    const char *dtn = dt == DRIVE_UNKNOWN ? "UNKNOWN" : dt == DRIVE_NO_ROOT_DIR ? "NO_ROOT_DIR" :
                      dt == DRIVE_REMOVABLE ? "REMOVABLE" : dt == DRIVE_FIXED ? "FIXED" :
                      dt == DRIVE_REMOTE ? "REMOTE" : dt == DRIVE_CDROM ? "CDROM" :
                      dt == DRIVE_RAMDISK ? "RAMDISK" : "?";
    printf("GetDriveTypeW   : %u (%s)\n", dt, dtn);

    wchar_t volpath[MAX_PATH + 1] = {0};
    SetLastError(0);
    BOOL vp = GetVolumePathNameW(root, volpath, MAX_PATH + 1);
    printf("GetVolumePathNmW: ok=%d err=%lu path=\"%ls\"\n", vp, GetLastError(), volpath);

    wchar_t volname1[MAX_PATH + 1] = {0};
    SetLastError(0);
    BOOL vn = GetVolumeNameForVolumeMountPointW(root, volname1, MAX_PATH + 1);
    printf("GetVolNameFMPW  : ok=%d err=%lu name=\"%ls\"\n", vn, GetLastError(), volname1);

    wchar_t volname2[MAX_PATH + 1] = {0}, fsname2[MAX_PATH + 1] = {0};
    DWORD serial2 = 0, maxcomp2 = 0, flags2 = 0;
    if (vn)
    {
        SetLastError(0);
        BOOL ok2 = GetVolumeInformationW(volname1, volname2, MAX_PATH, &serial2, &maxcomp2, &flags2,
                                         fsname2, MAX_PATH);
        printf("  via volume name: ok=%d err=%lu fs=\"%ls\" serial=%08lx flags=%08lx\n",
               ok2, GetLastError(), fsname2, serial2, flags2);
    }

    wchar_t volname3[MAX_PATH + 1] = {0}, fsname3[MAX_PATH + 1] = {0};
    DWORD serial3 = 0, maxcomp3 = 0, flags3 = 0;
    SetLastError(0);
    BOOL ok3 = GetVolumeInformationW(path, volname3, MAX_PATH, &serial3, &maxcomp3, &flags3,
                                     fsname3, MAX_PATH);
    printf("GetVolumeInfoW(path): ok=%d err=%lu fs=\"%ls\" serial=%08lx flags=%08lx\n",
           ok3, GetLastError(), fsname3, serial3, flags3);

    wchar_t volname[MAX_PATH + 1] = {0}, fsname[MAX_PATH + 1] = {0};
    DWORD serial = 0, maxcomp = 0, flags = 0;
    SetLastError(0);
    BOOL ok = GetVolumeInformationW(root, volname, MAX_PATH, &serial, &maxcomp, &flags, fsname, MAX_PATH);
    printf("GetVolumeInfoW  : ok=%d err=%lu vol=\"%ls\" fs=\"%ls\" serial=%08lx flags=%08lx\n",
           ok, GetLastError(), volname, fsname, serial, flags);
    if (ok) dump_flags(flags);

    ULARGE_INTEGER freeb = {}, total = {}, totalfree = {};
    SetLastError(0);
    BOOL d1 = GetDiskFreeSpaceExW(root, &freeb, &total, &totalfree);
    printf("GetDiskFreeSpEx : ok=%d err=%lu avail=%llu MB total=%llu MB\n",
           d1, GetLastError(),
           (unsigned long long)(freeb.QuadPart >> 20), (unsigned long long)(total.QuadPart >> 20));

    SetLastError(0);
    DWORD sec = 0, bps = 0, nfree = 0, ntotal = 0;
    BOOL d2 = GetDiskFreeSpaceW(root, &sec, &bps, &nfree, &ntotal);
    printf("GetDiskFreeSpW  : ok=%d err=%lu sec=%lu bps=%lu nfree=%lu ntotal=%lu\n",
           d2, GetLastError(), sec, bps, nfree, ntotal);

    DWORD attr = GetFileAttributesW(path);
    printf("GetFileAttrs    : %08lx dir=%d\n", attr, (attr != INVALID_FILE_ATTRIBUTES) && (attr & FILE_ATTRIBUTE_DIRECTORY));

    // write probe, the way an app checks it can put projects there
    wchar_t probe[MAX_PATH];
    _snwprintf(probe, MAX_PATH, L"%ls\\.writeprobe_tmp", path);
    SetLastError(0);
    HANDLE h = CreateFileW(probe, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
    printf("CreateFileW     : %p err=%lu\n", h, GetLastError());
    if (h != INVALID_HANDLE_VALUE) { DWORD w = 0; WriteFile(h, "x", 1, &w, NULL); CloseHandle(h); DeleteFileW(probe); }
}

int main(int argc, char **argv)
{
    printf("=== volprobe ===\n");
    if (argc > 1) {
        wchar_t w[1024];
        MultiByteToWideChar(CP_ACP, 0, argv[1], -1, w, 1024);
        dump_drive(w);
    } else {
        dump_drive(L"C:\\");
        dump_drive(L"C:\\users\\asdf\\AppData\\Local\\CapCut\\User Data\\Projects");
    }
    printf("=== end ===\n");
    return 0;
}
