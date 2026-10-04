#include <windows.h>
#include <stdio.h>

static void try_load(const char *what, const char *path, DWORD flags)
{
    HMODULE h;
    SetLastError(0);
    if (flags)
        h = LoadLibraryExA(path, NULL, flags);
    else
        h = LoadLibraryA(path);
    printf("%-10s %-70s -> %p err=%lu\n", what, path, (void *)h, (unsigned long)GetLastError());
}

int main(int argc, char **argv)
{
    char cwd[MAX_PATH];
    GetCurrentDirectoryA(sizeof(cwd), cwd);
    printf("cwd=%s\n", cwd);

    try_load("abs", "C:\\users\\asdf\\AppData\\Local\\CapCut\\Apps\\9.5.0.4050\\VEAngle\\libEGL.dll", 0);
    try_load("rel-ve", "ve_detector/libEGL.dll", 0);
    try_load("rel-ang", "VEAngle\\libEGL.dll", 0);
    try_load("gles-abs", "C:\\users\\asdf\\AppData\\Local\\CapCut\\Apps\\9.5.0.4050\\VEAngle\\libGLESv2.dll", 0);
    try_load("gles-rel", "VEAngle\\libGLESv2.dll", 0);
    try_load("cef-egl", "cef\\libEGL.dll", 0);
    if (argc > 1) try_load("argv", argv[1], 0);
    return 0;
}
