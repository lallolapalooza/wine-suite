/*
 * dataconvprobe.exe - the OLE DB conversion service, called the way the provider's GetData calls it.
 *
 * Why this exists: msolap's IRowset::GetData does not convert column values itself.  For a column bound
 * natively (the mode Power BI's ATL `CDynamicAccessor` uses) it hands the value - held internally as a
 * VARIANT - to the OLE DB data-conversion library, `oledb32!IDataConvert` (CLSID_OLEDB_CONVERSIONLIBRARY),
 * whose class object the provider gets from `oledb32.dll`.  Measured under Wine (docs/I8_BINDING_FIX.md),
 * that call returned E_NOTIMPL for `VARIANT -> DBTYPE_I8` and `VARIANT -> DBTYPE_BOOL`:
 *
 *     fixme:oledb:convert_DataConvert ...
 *     Unimplemented conversion 000c -> I8
 *
 * which the provider turns into a failed row read (`E_BADACCESSOR` per column, or `DB_E_ERRORSINCOMMAND`
 * when Power BI's forward-only property set is in effect) - the visual's "Error fetching data for this
 * visual".  Power BI binds an `I8` column as `I8` (and a `BOOL` column as `BOOL`), so those two
 * conversions are the whole of the failure; the neighbouring destinations (I4, UI8, R8, ...) are
 * implemented and work under both platforms.
 *
 * This probe drives that one call directly, with no Analysis Services engine, no msolap and no data:
 * it loads `oledb32.dll`, asks for the conversion class and prints the CanConvert/DataConvert result for
 * each source->destination pair of interest.  The same binary under two Wine builds is the A/B - the
 * conversion matrix of a build with the fix against a build without it.
 *
 * usage: dataconvprobe.exe [oledb32.dll path]      (default: whatever LoadLibrary finds)
 */
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <oleauto.h>
#include <oledb.h>
#include <msdadc.h>
#include <stdio.h>

/* The GUIDs are written out here rather than taken from msdaguid.h, whose `EXTERN_C const GUID` declaration
 * has no definition in a C build (msolapprobe.c does the same for its own CLSIDs).  Values: oledb32's
 * "OLE DB Data Conversion Library" class (dlls/oledb32/oledb32_classes.idl) and its IDataConvert interface
 * (include/msdadc.h). */
static const GUID CLSID_CONVERSIONLIBRARY_PROBE =
    {0xc8b522d1,0x5cf3,0x11ce,{0xad,0xe5,0x00,0xaa,0x00,0x44,0x77,0x3d}};
static const GUID IID_IDataConvert_PROBE =
    {0x0c733a8d,0x2a1c,0x11ce,{0xad,0xe5,0x00,0xaa,0x00,0x44,0x77,0x3d}};

static const char *dst_name( DBTYPE t )
{
    switch (t)
    {
    case DBTYPE_I1:   return "DBTYPE_I1";
    case DBTYPE_I2:   return "DBTYPE_I2";
    case DBTYPE_I4:   return "DBTYPE_I4";
    case DBTYPE_I8:   return "DBTYPE_I8";
    case DBTYPE_UI1:  return "DBTYPE_UI1";
    case DBTYPE_UI2:  return "DBTYPE_UI2";
    case DBTYPE_UI4:  return "DBTYPE_UI4";
    case DBTYPE_UI8:  return "DBTYPE_UI8";
    case DBTYPE_R4:   return "DBTYPE_R4";
    case DBTYPE_R8:   return "DBTYPE_R8";
    case DBTYPE_BOOL: return "DBTYPE_BOOL";
    case DBTYPE_DATE: return "DBTYPE_DATE";
    case DBTYPE_BSTR: return "DBTYPE_BSTR";
    }
    return "DBTYPE_?";
}

static const char *status_name( DBSTATUS s )
{
    switch (s)
    {
    case DBSTATUS_S_OK:              return "S_OK";
    case DBSTATUS_S_ISNULL:          return "S_ISNULL";
    case DBSTATUS_E_BADACCESSOR:     return "E_BADACCESSOR";
    case DBSTATUS_E_DATAOVERFLOW:    return "E_DATAOVERFLOW";
    case DBSTATUS_E_SIGNMISMATCH:    return "E_SIGNMISMATCH";
    case DBSTATUS_E_CANTCONVERTVALUE:return "E_CANTCONVERTVALUE";
    }
    return "?";
}

static void print_value( DBTYPE t, const void *p, DBLENGTH len )
{
    switch (t)
    {
    case DBTYPE_I1:  printf( "%d", *(const signed char *)p ); break;
    case DBTYPE_I2:  printf( "%d", *(const short *)p ); break;
    case DBTYPE_I4:  printf( "%ld", *(const long *)p ); break;
    case DBTYPE_I8:  printf( "%lld", *(const long long *)p ); break;
    case DBTYPE_UI1: printf( "%u", *(const unsigned char *)p ); break;
    case DBTYPE_UI2: printf( "%u", *(const unsigned short *)p ); break;
    case DBTYPE_UI4: printf( "%lu", *(const unsigned long *)p ); break;
    case DBTYPE_UI8: printf( "%llu", *(const unsigned long long *)p ); break;
    case DBTYPE_R8:  printf( "%g", *(const double *)p ); break;
    case DBTYPE_BOOL:printf( "%s", *(const VARIANT_BOOL *)p == VARIANT_FALSE ? "VARIANT_FALSE" : "VARIANT_TRUE" ); break;
    default:         printf( "<%lu bytes>", (unsigned long)len ); break;
    }
}

/* One row of the matrix: a source VARIANT and the destination type a client would bind. */
struct dc_case
{
    const char *src;
    VARIANT     v;
    DBTYPE      dst;
};

int main( int argc, char **argv )
{
    HMODULE mod;
    FARPROC gco;
    IClassFactory *cf = NULL;
    IDataConvert *dc = NULL;
    HRESULT hr;
    unsigned int i, bad = 0;
    struct dc_case cases[10];
    unsigned int ncases = 0;
    VARIANT v;

    setvbuf( stdout, NULL, _IONBF, 0 );

    if (argc > 1)
    {
        WCHAR wide[MAX_PATH];
        MultiByteToWideChar( CP_ACP, 0, argv[1], -1, wide, MAX_PATH );
        mod = LoadLibraryW( wide );
    }
    else
        mod = LoadLibraryW( L"oledb32.dll" );

    printf( "DATA CONVERT probe\n" );
    printf( "  oledb32      %s\n", mod ? (argc > 1 ? argv[1] : "oledb32.dll (from the search path)") : "(not loaded)" );
    if (!mod)
    {
        /* The DLL is not on the search path; the OLE DB components live where the registry points
         * (`InprocServer32` of CLSID_OLEDB_CONVERSIONLIBRARY), which is what the provider uses. */
        mod = LoadLibraryW( L"C:\\Program Files\\Common Files\\System\\OLE DB\\oledb32.dll" );
        printf( "  oledb32      %s\n", mod ? "Common Files\\System\\OLE DB\\oledb32.dll" : "(not loaded)" );
    }
    if (!mod) { printf( "  LoadLibrary failed, GetLastError=%lu\n", (unsigned long)GetLastError() ); return 1; }
    {
        WCHAR path[MAX_PATH];
        if (GetModuleFileNameW( mod, path, MAX_PATH ))
            printf( "  loaded from  %ls\n", path );
    }

    hr = CoInitializeEx( NULL, COINIT_APARTMENTTHREADED );
    printf( "  CoInitializeEx                           hr=0x%08lX\n", (unsigned long)hr );

    gco = GetProcAddress( mod, "DllGetClassObject" );
    hr = gco ? ((HRESULT (WINAPI *)(REFCLSID, REFIID, void **))gco)(
                   &CLSID_CONVERSIONLIBRARY_PROBE, &IID_IClassFactory, (void **)&cf ) : E_FAIL;
    printf( "  DllGetClassObject(CONVERSIONLIBRARY)     hr=0x%08lX\n", (unsigned long)hr );
    if (FAILED(hr)) { printf( "  (no conversion class - nothing to test)\n" ); return 1; }

    hr = IClassFactory_CreateInstance( cf, NULL, &IID_IDataConvert_PROBE, (void **)&dc );
    printf( "  CreateInstance(IID_IDataConvert)         hr=0x%08lX\n", (unsigned long)hr );
    if (FAILED(hr)) { printf( "  (no IDataConvert - nothing to test)\n" ); return 1; }

    /* the source variants: what the engine's cells look like to the provider */
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_I8;
    VariantInit( &v ); v.vt = VT_I8;    V_I8(&v) = 1234567890123LL;          cases[ncases].src = "VARIANT(VT_I8)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_I8;
    VariantInit( &v ); v.vt = VT_BOOL;  V_BOOL(&v) = VARIANT_TRUE;           cases[ncases].src = "VARIANT(VT_BOOL)";      cases[ncases].v = v; cases[ncases++].dst = DBTYPE_BOOL;
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_BOOL;
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 0;                          cases[ncases].src = "VARIANT(VT_I4=0)";      cases[ncases].v = v; cases[ncases++].dst = DBTYPE_BOOL;
    /* controls: the bound-as-X cases the provider already converted before the fix */
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_I4;
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_UI8;
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_UI4;
    VariantInit( &v ); v.vt = VT_R8;    v.dblVal = 1.5;                      cases[ncases].src = "VARIANT(VT_R8)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_R8;
    VariantInit( &v ); v.vt = VT_I4;    v.lVal = 1;                          cases[ncases].src = "VARIANT(VT_I4)";        cases[ncases].v = v; cases[ncases++].dst = DBTYPE_I1;

    printf( "\n  %-20s -> %-12s %-12s %-12s %-16s %-6s %s\n", "source", "destination", "CanConvert",
            "DataConvert", "value", "dbtatus", "dst_len" );
    for (i = 0; i < ncases; i++)
    {
        union { long long i8; ULONGLONG u8; double r8; VARIANT_BOOL b; long i4; unsigned long u4; unsigned char buf[16]; } out;
        DBSTATUS status = 0xdeadbeef;
        DBLENGTH dst_len = 0;
        HRESULT can, conv;

        memset( &out, 0, sizeof(out) );
        can = IDataConvert_CanConvert( dc, DBTYPE_VARIANT, cases[i].dst );
        conv = IDataConvert_DataConvert( dc, DBTYPE_VARIANT, cases[i].dst, sizeof(VARIANT), &dst_len,
                                         &cases[i].v, &out, sizeof(out), DBSTATUS_S_OK, &status, 0, 0,
                                         DBDATACONVERT_DEFAULT );
        printf( "  %-20s -> %-12s 0x%08lX   0x%08lX   ", cases[i].src, dst_name( cases[i].dst ),
                (unsigned long)can, (unsigned long)conv );
        if (SUCCEEDED( conv ))
            print_value( cases[i].dst, &out, dst_len );
        else
            printf( "-" );
        printf( "%-16s %-6s %lu\n", status == 0xdeadbeef ? "(untouched)" : status_name( status ),
                status == 0xdeadbeef ? "(untouched)" : "", (unsigned long)dst_len );
        if (FAILED( conv ) && (cases[i].dst == DBTYPE_I8 || cases[i].dst == DBTYPE_BOOL)) bad++;
    }

    printf( "\n  verdict: VARIANT -> I8/BOOL %s\n", bad ? "FAILED" : "converted" );
    IDataConvert_Release( dc );
    IClassFactory_Release( cf );
    return bad ? 1 : 0;
}
