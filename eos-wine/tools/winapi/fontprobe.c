/* fontprobe.c — list the font families GDI enumerates and what a family name resolves to.
 *
 * build: x86_64-w64-mingw32-gcc -O1 -o fontprobe.exe fontprobe.c -lgdi32 -luser32
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static int total;
static int hits;

static int CALLBACK cb(const LOGFONTW *lf, const TEXTMETRICW *tm, DWORD type, LPARAM lp)
{
    char name[256];
    WideCharToMultiByte(CP_ACP, 0, lf->lfFaceName, -1, name, sizeof name, NULL, NULL);
    (void)tm; (void)type; (void)lp;
    total++;
    if (!_stricmp(name, "Arial") || !_stricmp(name, "Verdana") ||
        !_stricmp(name, "Liberation Sans") || !_stricmp(name, "Tahoma") ||
        !_stricmp(name, "DejaVu Sans") || !_stricmp(name, "MS Sans Serif")) {
        printf("  FOUND family \"%s\" charset=%d type=%lx\n", name, lf->lfCharSet, type);
        hits++;
    }
    return 1;
}

static void resolve(HDC dc, const char *face)
{
    LOGFONTA lf;
    HFONT f;
    char got[256] = "";
    memset(&lf, 0, sizeof lf);
    lf.lfHeight = -12;
    lf.lfCharSet = DEFAULT_CHARSET;
    strncpy(lf.lfFaceName, face, LF_FACESIZE - 1);
    f = CreateFontIndirectA(&lf);
    if (f) {
        HGDIOBJ old = SelectObject(dc, f);
        GetTextFaceA(dc, sizeof got, got);
        SelectObject(dc, old);
        DeleteObject(f);
    }
    printf("  CreateFont(\"%s\") -> GetTextFace \"%s\"\n", face, got);
}

int main(void)
{
    HDC dc;
    LOGFONTW lf;
    setvbuf(stdout, NULL, _IONBF, 0);
    dc = GetDC(NULL);
    printf("=== resolve ===\n");
    resolve(dc, "Arial");
    resolve(dc, "Verdana");
    resolve(dc, "Tahoma");
    printf("=== enumerate all families ===\n");
    memset(&lf, 0, sizeof lf);
    lf.lfCharSet = DEFAULT_CHARSET;
    EnumFontFamiliesExW(dc, &lf, cb, 0, 0);
    printf("  total families=%d interesting=%d\n", total, hits);
    ReleaseDC(NULL, dc);
    return 0;
}
