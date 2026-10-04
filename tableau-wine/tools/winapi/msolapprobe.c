/*
 * msolapprobe.c — reproduce Power BI's MSOLAP (OLE DB) connect sequence with the provider Power BI ships,
 * printing the HRESULT of every step.  The same binary runs on Windows and under Wine, so the behaviour of
 * the two is diffed rather than guessed (same method as tools/winapi/roprobe.c / asimp.c).
 *
 * It copies what Microsoft.PowerBI.MsolapWrapper.dll (C++/CLI) does, decompiled:
 *   MsolapWrapper.MsolapClassFactory.CreateDbInitialize:
 *       h = LoadLibraryExW(<this dll dir>\msolap.dll, NULL,
 *                          LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);   // 0x1100
 *       DllGetClassObject(&CLSID_MSOLAP, &IID_IClassFactory, &pcf)
 *       pcf->CreateInstance(NULL, &IID_IDBInitialize, &dbinit)
 *   MsolapWrapper.Connection.Open:
 *       SetTracerForDbInit(dbinit)                      (optional: IID_IASTracerContext "62b9e9ad-…")
 *       SetConnectionProperties(dbinit, sessionId):
 *           dbinit->QueryInterface(IID_IDBProperties, &props)
 *           props->SetProperties(1, { DBPROPSET_DBINIT, DBPROP_INIT_PROVIDERSTRING = <connection string> })
 *             (+ { DBPROPSET_MSOLAPINIT = A07CCD04-…, property 4168 = <session id> } when a session id is given)
 *       dbinit->Initialize()
 *
 * usage:  msolapprobe.exe <msolap.dll path | -> <connection string> [--noconnect] [--query <text>]
 *         "-" as the dll path means: let the OS find "msolap" on the module search path.
 *
 * Instrumentation added while working FINDINGS M37 (all optional):
 *   --hook    IAT hooks on the provider's GetLastError/SetLastError/HeapValidate, with a backtrace on each read
 *   --sspi    detour of secur32!InitSecurityInterfaceW (by name, address-matched) so every SSPI call the provider
 *             makes through the returned table — and its status — becomes visible
 *   --tracer  install an IMsolapTracer on the provider's IASTracerContext (the provider's own messages)
 *   --gpa     log every import the provider resolves dynamically (perturbs it: opt-in)
 *   --spnego  report Wine's raw-NTLM flow in the Windows Negotiate/SPNEGO round shape (a causality test, it does
 *             not change Wine)
 *   --sink    fill the trace-queue owner's sink pointer if it is NULL (experiment, see M37)
 *
 * Exit code: 0 when the whole sequence (and the query, if one was asked for) succeeded.
 * Build:  x86_64-w64-mingw32-gcc -O1 -o bin/msolapprobe.exe msolapprobe.c -lole32 -loleaut32 -luuid -ladvapi32 -lpsapi
 */
#define COBJMACROS
#define DBINITCONSTANTS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <oledb.h>
#include <stdio.h>
#include <string.h>
#define SECURITY_WIN32
#include <psapi.h>
#include <sspi.h>

/* From the decompiled MsolapWrapper: MsolapClassFactory's static ctor sets MsolapClsId =
 * new Guid("DBC724B0-DD86-4772-BB5A-FCC6CAB2FC1A") and passes *that* to DllGetClassObject.
 * (The assembly's other constant, A07CCD0C-8148-11D0-87BB-00C04FC33942, is the guidPropertySet of the
 * session-id DBPROP in DBPROPSET_MSOLAPINIT — it is not the provider's class object.) */
static const GUID CLSID_MSOLAP_PROBE =
    { 0xDBC724B0, 0xDD86, 0x4772, { 0xBB, 0x5A, 0xFC, 0xC6, 0xCA, 0xB2, 0xFC, 0x1A } };
static const GUID DBPROPSET_MSOLAPINIT_PROBE =
    { 0xA07CCD04, 0x8148, 0x11D0, { 0x87, 0xBB, 0x00, 0xC0, 0x4F, 0xC3, 0x39, 0x42 } };
static const GUID IID_IASTracerContext_PROBE =
    { 0x62B9E9AD, 0xE0E5, 0x4AB2, { 0x96, 0x26, 0x24, 0x9E, 0x06, 0xFA, 0x5B, 0x9E } };

static void step(const char *what, HRESULT hr)
{
    printf("  %-42s hr=0x%08lX  %s   GetLastError=%lu\n",
           what, (unsigned long)hr, SUCCEEDED(hr) ? "OK" : "FAIL", (unsigned long)GetLastError());
    fflush(stdout);
}

/*
 * The provider's trace callback.  MsolapWrapper.Connection.Open installs one (its C++/CLI NativeProxyTracer) on
 * the IDBInitialize object through IASTracerContext {62b9e9ad-e0e5-4ab2-9626-249e06fa5b9e}; every "[msolap] …"
 * line Power BI logs comes through it, with the provider's own source file and line — the single best view of
 * what the provider thinks is wrong.
 *
 * The layout is *not* COM's: the decompiled Microsoft.PowerBI.MsolapWrapper.dll (NativeProxyTracer's vtable,
 * ??_7NativeProxyTracer@@6B@ = five entries in this order, and the method bodies behind them) gives
 *
 *     slot 0  Trace(level, BSTR message)
 *     slot 1  SanitizedTrace(level, BSTR message)
 *     slot 2  AddRef() -> ULONG
 *     slot 3  Release() -> ULONG
 *     slot 4  QueryInterface(riid, ppv) -> HRESULT   (the real one always returns E_NOINTERFACE)
 *
 * and the message is a BSTR (`Marshal.PtrToStringBSTR` in the wrapper), not a plain WCHAR*.  Getting either of
 * those wrong makes SetTracer crash inside the provider's own error formatter instead of returning.
 */
typedef struct {
    void (*Trace)(void *, int level, const WCHAR *message);          /* slot 0 */
    void (*SanitizedTrace)(void *, int level, const WCHAR *message); /* slot 1 */
    ULONG (*AddRef)(void *);                                        /* slot 2 */
    ULONG (*Release)(void *);                                       /* slot 3 */
    HRESULT (*QueryInterface)(void *, const GUID *, void **);        /* slot 4 */
} IMsolapTracerVtbl;

/* A provider hands back BSTRs whose pointer cannot be trusted: this probe read one (a record from msolap for a
 * DB_E_BADCHAPTER) whose four-byte length prefix was garbage, and dereferencing it crashed the probe.  Every
 * string read therefore goes through VirtualQuery first. */
static int mem_readable( const void *p, size_t n )
{
    MEMORY_BASIC_INFORMATION mbi;
    if (!p) return 0;
    if (VirtualQuery( p, &mbi, sizeof(mbi) ) != sizeof(mbi)) return 0;
    if (mbi.State != MEM_COMMIT) return 0;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return 0;
    return (const char *)p + n <= (const char *)mbi.BaseAddress + mbi.RegionSize;
}

static int bstr_len( const WCHAR *s, ULONG *out )
{
    ULONG len;
    if (!mem_readable( (const char *)s - 4, 4 )) return 0;
    len = *(const ULONG *)((const char *)s - 4);
    if (len % 2 || len > 65536) return 0;
    if (!mem_readable( s, (size_t)len + 2 )) return 0;
    *out = len;
    return 1;
}

static void print_bstr(const WCHAR *s)
{
    ULONG len, i;
    if (!s) { printf("(null)"); return; }
    if (!bstr_len( s, &len )) { printf("<not a BSTR: %p>", (const void *)s); return; }
    for (i = 0; i < len / 2; i++) putchar((s[i] >= 32 && s[i] < 127) ? (char)s[i] : (s[i] == '\n' ? '\n' : '.'));
}

static void trace_common(const char *which, int level, const WCHAR *msg)
{
    printf("  [msolap %s %d] ", which, level);
    print_bstr(msg);
    printf("\n");
    fflush(stdout);
}

static void tracer_Trace(void *self, int level, const WCHAR *msg)          { (void)self; trace_common("trace", level, msg); }
static void tracer_SanitizedTrace(void *self, int level, const WCHAR *msg) { (void)self; trace_common("trace", level, msg); }
static ULONG tracer_AddRef(void *self) { (void)self; return 2; }
static ULONG tracer_Release(void *self) { (void)self; return 1; }
static HRESULT tracer_QueryInterface(void *self, const GUID *riid, void **ppv)
{
    (void)self; (void)riid;
    if (ppv) *ppv = NULL;
    return E_NOINTERFACE;   /* what the real NativeProxyTracer answers */
}

static IMsolapTracerVtbl g_tracer_vtbl = {
    tracer_Trace, tracer_SanitizedTrace, tracer_AddRef, tracer_Release, tracer_QueryInterface
};

/* IASTracerContext: IUnknown + SetTracer(IMsolapTracer*).  The wrapper calls the method at vtable offset 24,
 * so SetTracer is slot 3.  The object comes from the provider's own QueryInterface, so it is reached through
 * its vtable pointer, not by laying a struct over the interface pointer. */
/* The provider's SetTracer reaches a sub-object at +0x278 and flushes queued trace records through its first field
 * (`sink->vtable[4](sink, level, message)`), and it takes that branch when the field at +0xd8 is NULL.  Both fields
 * are printed, and if the queue owner's sink is NULL it is filled with one of ours, so the provider's queued
 * messages have somewhere to go instead of dereferencing NULL. */
static void *g_sink_vtbl[8];

static int g_tracer_installed;
static int g_sink_fix;

/* --tracer-late: MsolapWrapper installs its tracer right after CreateInstance, but the provider's trace-queue
 * owner (the field SetTracer flushes through) is still NULL at that point and the install crashes.  By the first
 * SSPI call the provider is inside Initialize() and the queue exists, so install then and get the messages that
 * describe the connect path. */
static int g_tracer_late;
static IDBInitialize *g_dbinit_late;

static void install_tracer(IDBInitialize *dbinit)
{
    void *ctx = NULL;
    void **vtbl;
    HRESULT hr = IDBInitialize_QueryInterface(dbinit, &IID_IASTracerContext_PROBE, &ctx);
    if (FAILED(hr) || !ctx) {
        printf("  QueryInterface(IASTracerContext)          hr=0x%08lX (provider trace unavailable)\n",
               (unsigned long)hr);
        return;
    }
    vtbl = *(void ***)ctx;
    printf("  tracer ctx=%p vtbl=%p  [+0xd8]=%p [+0x278]=%p (queue owner) [*queue]=%p\n", ctx, (void *)vtbl,
           ((void **)ctx)[0xd8 / 8], ((void **)ctx)[0x278 / 8], *(void **)((char *)ctx + 0x278));
    if (g_sink_fix) {
        void *owner = *(void **)((char *)ctx + 0x278);
        if (owner && !*(void **)owner) {
            g_sink_vtbl[4] = (void *)tracer_Trace;
            *(void **)owner = g_sink_vtbl;
            printf("  [probe] filled the trace-queue sink %p -> our vtable %p\n", owner, (void *)g_sink_vtbl);
        }
    }
    hr = ((HRESULT (WINAPI *)(void *, void *))vtbl[3])(ctx, &g_tracer_vtbl);
    if (SUCCEEDED(hr)) g_tracer_installed = 1;
    printf("  IASTracerContext::SetTracer(IMsolapTracer) hr=0x%08lX  (ctx=%p vtbl=%p)\n",
           (unsigned long)hr, ctx, (void *)vtbl);
    fflush(stdout);
}

/* Read a whole text file into a static buffer.  --query-file exists because a DAX statement is full of quotes and
 * no shell passes them faithfully (PowerShell 5.1 drops them when building a native command line, measured). */
static char *read_text_file( const char *path )
{
    static char buf[65536];
    FILE *f = fopen( path, "rb" );
    size_t n;
    if (!f) { printf("  (--query-file: cannot open %s)\n", path); return NULL; }
    n = fread( buf, 1, sizeof(buf) - 1, f );
    fclose( f );
    buf[n] = 0;
    return buf;
}

/* mingw's oledb.h shims IErrorRecords but declares no OLE DB DBERROR (its GetBasicErrorInfo prototype expects the
 * COM ERRORINFO), and the field this experiment needs most - dwMinor - only exists in the OLE DB structure.  The
 * layout is the documented OLE DB one; only the leading fields are ever read here. */
/* The documented extended error record (there is no DBERROR in mingw's oledb.h).  The order matters: the
 * layout is {source, description, helpfile, helpcontext, reserved, hrError, dwMinor, clsid, iid, dispid,
 * wNative, sqlstate} — an `iid` field sat missing here until a real record was read, which shifted wNative
 * and printed garbage (and the BSTRs are printed through print_bstr, which validates the length prefix
 * instead of trusting the pointer). */
typedef struct probe_dberror {
    BSTR    bstrSource;
    BSTR    bstrDescription;
    BSTR    bstrHelpFile;
    DWORD   dwHelpContext;
    PVOID   pvReserved;
    HRESULT hrError;
    DWORD   dwMinor;
    CLSID   clsid;
    IID     iid;
    DISPID  dispid;
    LPARAM  wNative;
    BSTR    bstrSQLState;
} probe_dberror;

/* Enumerate the OLE DB error *records*, not just the summary.  DB_E_ERRORSINCOMMAND with dwMinor=0 is the provider
 * saying it rejected something, and the records are where a provider names what: DBERROR carries hrError, dwMinor,
 * the native error, the SQL state and a description.  This is the artefact that separates "Wine's provider found a
 * real problem" from "Wine's provider is complaining about its own environment". */
static void dump_error_records( const char *when )
{
    IErrorInfo *ei = NULL;
    IErrorRecords *er = NULL;
    ULONG n = 0, i;

    if (FAILED(GetErrorInfo(0, &ei)) || !ei) {
        printf("  [%s] GetErrorInfo: no error info\n", when);
        return;
    }
    if (SUCCEEDED(IErrorInfo_QueryInterface(ei, &IID_IErrorRecords, (void **)&er)) && er) {
        ULONG cnt = 0;
        if (SUCCEEDED(IErrorRecords_GetRecordCount(er, &cnt))) n = cnt;
        printf("  [%s] OLE DB error records: %lu\n", when, (unsigned long)n);
        for (i = 0; i < n && i < 8; i++) {
            probe_dberror dberr;
            ERRORINFO info;
            IErrorInfo *rec = NULL;
            unsigned b;
            memset( &dberr, 0, sizeof(dberr) );
            memset( &info, 0, sizeof(info) );
            if (SUCCEEDED(IErrorRecords_GetBasicErrorInfo( er, i, (void *)&dberr ))) {
                /* Two readings of the same 72 bytes, because the two candidate layouts disagree about where
                 * everything sits: the COM ERRORINFO the header declares, and the OLE DB extended record.
                 * The raw bytes are printed too, so the reading can be checked rather than believed. */
                memcpy( &info, &dberr, sizeof(info) );
                printf("  [%s] record[%lu] raw ", when, (unsigned long)i);
                for (b = 0; b < 48 && b < sizeof(dberr); b++) printf("%02X", ((unsigned char *)&dberr)[b]);
                printf("\n");
                printf("  [%s] record[%lu] ERRORINFO hrError=0x%08lX dwMinor=0x%08lX dispid=%ld\n", when,
                       (unsigned long)i, (unsigned long)info.hrError, (unsigned long)info.dwMinor,
                       (long)info.dispid);
                printf("  [%s] record[%lu] extended hrError=0x%08lX dwMinor=0x%08lX wNative=%lu sqlstate=", when,
                       (unsigned long)i, (unsigned long)dberr.hrError, (unsigned long)dberr.dwMinor,
                       (unsigned long)dberr.wNative);
                if (dberr.bstrSQLState) print_bstr( dberr.bstrSQLState ); else printf("(none)");
                printf("\n");
                if (dberr.bstrDescription) {
                    printf("  [%s] record[%lu] extended description=\"", when, (unsigned long)i);
                    print_bstr( dberr.bstrDescription );
                    printf("\"\n");
                }
                if (dberr.bstrSource) {
                    printf("  [%s] record[%lu] extended source=\"", when, (unsigned long)i);
                    print_bstr( dberr.bstrSource );
                    printf("\"\n");
                }
            }
            if (SUCCEEDED(IErrorRecords_GetErrorInfo( er, i, 0, &rec )) && rec) {
                BSTR d = NULL, s = NULL;
                if (SUCCEEDED(IErrorInfo_GetDescription( rec, &d )) && d) {
                    printf("  [%s] record[%lu] IErrorInfo::GetDescription=\"", when, (unsigned long)i);
                    print_bstr( d );
                    printf("\"\n");
                    SysFreeString( d );
                }
                if (SUCCEEDED(IErrorInfo_GetSource( rec, &s )) && s) {
                    printf("  [%s] record[%lu] IErrorInfo::GetSource=\"", when, (unsigned long)i);
                    print_bstr( s );
                    printf("\"\n");
                    SysFreeString( s );
                }
                IErrorInfo_Release( rec );
            }
        }
        IErrorRecords_Release( er );
    } else {
        printf("  [%s] (error object exposes no IErrorRecords)\n", when);
    }
    IErrorInfo_Release( ei );
    fflush( stdout );
}

/* --app-props: the property set Power BI's wrapper sets on the command *before* it executes, decompiled from
 * MsolapWrapper.CommandPropertySetCollection.AddProperty (values measured in the app's own trace line
 * "Running the query. Memory Limit=1048576, Timeout=225, RequestPriority=Normal, RequestExecutionMetrics=[Basic],
 * ApplicationContext=, MaximumRowsPerResultSet=-1, UseForwardOnly=True"):
 *
 *   DBPROPSET_ROWSET     DBPROP 0x0E = VARIANT_FALSE (required)   ] the triplet CommandProperties.ForwardOnly
 *                        DBPROP_CANFETCHBACKWARDS (0x12) = FALSE   ] emits when true
 *                        DBPROP_CANSCROLLBACKWARDS (0x15) = FALSE  ]
 *                        DBPROP_COMMANDTIMEOUT (0x22) = 225        (CommandTimeout)
 *                        DBPROP_MAXROWS (0x49) = -1                 (MaximumRows)
 *   DBPROPSET_MDCOMMAND  (FF830898-B1FA-4FEF-AA92-3E5960B30F95)
 *                        4209 = 1048576 (MemoryLimit), 4221 = 2 (RequestPriority: NORMAL),
 *                        4224 = 1 (ExecutionMetrics: MSMD_EXECUTIONMETRICS_BASIC)
 *
 * A rowset's answer to GetNextRows/GetData can legitimately depend on these (forward-only vs scrollable decides
 * whether the provider may have to serve rows backwards), so "the probe answered this" only means the app will
 * answer it too if the probe asks with the same properties. */
static const GUID DBPROPSET_MDCOMMAND_PROBE =
    { 0xFF830898, 0xB1FA, 0x4FEF, { 0xAA, 0x92, 0x3E, 0x59, 0x60, 0xB3, 0x0F, 0x95 } };

static void set_bool_prop( DBPROP *p, DBPROPID id, DWORD options, VARIANT_BOOL v )
{
    VariantInit( &p->vValue );
    p->dwPropertyID = id;
    p->dwOptions    = options;
    p->dwStatus     = 0;
    p->colid        = DB_NULLID;
    p->vValue.vt    = VT_BOOL;
    p->vValue.boolVal = v;
}

static void set_i4_prop( DBPROP *p, DBPROPID id, DWORD options, LONG v )
{
    VariantInit( &p->vValue );
    p->dwPropertyID = id;
    p->dwOptions    = options;
    p->dwStatus     = 0;
    p->colid        = DB_NULLID;
    p->vValue.vt    = VT_I4;
    p->vValue.lVal  = v;
}

static void apply_app_props( IUnknown *cmdobj )
{
    ICommandProperties *cp = NULL;
    DBPROP rp[5];
    DBPROP mp[3];
    DBPROPSET sets[2];
    HRESULT hr;
    unsigned i;

    memset( rp, 0, sizeof(rp) );
    memset( mp, 0, sizeof(mp) );
    set_bool_prop( &rp[0], 0x0E, DBPROPOPTIONS_REQUIRED, VARIANT_FALSE );
    set_bool_prop( &rp[1], DBPROP_CANFETCHBACKWARDS, DBPROPOPTIONS_OPTIONAL, VARIANT_FALSE );
    set_bool_prop( &rp[2], DBPROP_CANSCROLLBACKWARDS, DBPROPOPTIONS_OPTIONAL, VARIANT_FALSE );
    set_i4_prop  ( &rp[3], DBPROP_COMMANDTIMEOUT, DBPROPOPTIONS_REQUIRED, 225 );
    set_i4_prop  ( &rp[4], DBPROP_MAXROWS, DBPROPOPTIONS_REQUIRED, -1 );
    set_i4_prop  ( &mp[0], 4209, DBPROPOPTIONS_REQUIRED, 1048576 );  /* MemoryLimit */
    set_i4_prop  ( &mp[1], 4221, DBPROPOPTIONS_REQUIRED, 2 );        /* RequestPriority = NORMAL */
    set_i4_prop  ( &mp[2], 4224, DBPROPOPTIONS_REQUIRED, 1 );        /* ExecutionMetrics = BASIC */

    sets[0].guidPropertySet = DBPROPSET_ROWSET;
    sets[0].cProperties     = 5;
    sets[0].rgProperties    = rp;
    sets[1].guidPropertySet = DBPROPSET_MDCOMMAND_PROBE;
    sets[1].cProperties     = 3;
    sets[1].rgProperties    = mp;

    hr = IUnknown_QueryInterface( cmdobj, &IID_ICommandProperties, (void **)&cp );
    step( "QueryInterface(ICommandProperties)", hr );
    if (FAILED(hr) || !cp) return;
    hr = ICommandProperties_SetProperties( cp, 2, sets );
    step( "ICommandProperties::SetProperties(app set)", hr );
    for (i = 0; i < 5; i++)
        printf( "  DBPROP_ROWSET[%u] 0x%04lX dwStatus=0x%08lX%s\n", i, (unsigned long)rp[i].dwPropertyID,
                (unsigned long)rp[i].dwStatus, rp[i].dwStatus ? "  (FAILED)" : "" );
    for (i = 0; i < 3; i++)
        printf( "  DBPROP_MDCOMMAND[%u] %lu dwStatus=0x%08lX%s\n", i, (unsigned long)mp[i].dwPropertyID,
                (unsigned long)mp[i].dwStatus, mp[i].dwStatus ? "  (FAILED)" : "" );
    ICommandProperties_Release( cp );
    fflush( stdout );
}

static int g_app_props;   /* --app-props: set Power BI's own command property set before executing */

/* ---- flags used by the shaped-request replay (see docs/SHAPED_REPLAY.md) --------------------------------
 * These exist because the app's read is not a plain `GetNextRows`/`GetData` with every column bound as a
 * string: the wrapper is ATL (`CCommand<CDynamicAccessor, MsolapWrapper::CChapterBulkRowset, CMultipleResults>`),
 * so it *binds every column with its own OLE DB type* and reads whole rows through one accessor.  A provider
 * that answers a WSTR-bound read can still fail a native-bound one, so both modes have to be measurable.
 *
 *   --columns        print every column's OLE DB type/size/flags; name a DBTYPE_HCHAPTER column explicitly
 *                    (that type is what `DataReader.GetChildReader` turns into a child reader)
 *   --native         bind each column with its own type instead of DBTYPE_WSTR (ATL's CDynamicAccessor)
 *   --fetch N        rows per IRowset::GetNextRows call (default 1 = the wrapper's setting)
 *   --parent         query-interface the returned rowset for IParentRowset and walk its chapters
 *   --exec-iid X     force the interface the command is executed for: `rows` (IID_IRowset) or `multi`
 *                    (IID_IMultipleResults, what `MsolapWrapper.CCommandWrapper.OpenWithMultipleResultsOnly` asks for)
 *   --status         print the DBSTATUS symbol of every column in every row (default: only non-OK ones)
 * -------------------------------------------------------------------------------------------------------- */
static int g_columns, g_native, g_status, g_fetch = 1, g_parent, g_exec_iid;  /* g_exec_iid: 0 auto, 1 rows, 2 multi */
static int g_skip_col, g_only_col;   /* --skip-col N / --only-col N: bisect an accessor that the provider rejects */
static int g_big_buffers;            /* --big-buffers: cbMaxLen=2048 for every column, whatever its type */
static int g_force_type;             /* --force-type 0xNN: bind every column as that DBTYPE instead of its own */

static const char *status_name( DBSTATUS s )
{
    switch (s) {
    case DBSTATUS_S_OK:                  return "S_OK";
    case DBSTATUS_S_ISNULL:              return "S_ISNULL";
    case DBSTATUS_S_TRUNCATED:           return "S_TRUNCATED";
    case DBSTATUS_S_DEFAULT:             return "S_DEFAULT";
    case DBSTATUS_E_BADACCESSOR:         return "E_BADACCESSOR";
    case DBSTATUS_E_CANTCONVERTVALUE:    return "E_CANTCONVERTVALUE";
    case DBSTATUS_E_SIGNMISMATCH:        return "E_SIGNMISMATCH";
    case DBSTATUS_E_DATAOVERFLOW:        return "E_DATAOVERFLOW";
    case DBSTATUS_E_CANTCREATE:          return "E_CANTCREATE";
    case DBSTATUS_E_UNAVAILABLE:         return "E_UNAVAILABLE";
    case DBSTATUS_E_PERMISSIONDENIED:    return "E_PERMISSIONDENIED";
    case DBSTATUS_E_INTEGRITYVIOLATION:  return "E_INTEGRITYVIOLATION";
    case DBSTATUS_E_SCHEMAVIOLATION:     return "E_SCHEMAVIOLATION";
    case DBSTATUS_E_BADSTATUS:           return "E_BADSTATUS";
    default:                             return "?";
    }
}

static DBLENGTH type_len( WORD wType, DBLENGTH col_size )
{
    switch (wType & ~DBTYPE_BYREF) {
    case DBTYPE_BYTES: case DBTYPE_STR: case DBTYPE_WSTR: case DBTYPE_BSTR:
        return (col_size && col_size < 0x100000) ? col_size : 2048;
    case DBTYPE_VARIANT:      return sizeof(VARIANT);
    case DBTYPE_I1: case DBTYPE_UI1:                                  return 1;
    case DBTYPE_I2: case DBTYPE_UI2: case DBTYPE_BOOL:                return 2;
    case DBTYPE_I4: case DBTYPE_UI4: case DBTYPE_R4:                  return 4;
    case DBTYPE_I8: case DBTYPE_UI8: case DBTYPE_R8: case DBTYPE_CY:
    case DBTYPE_DATE:                                                 return 8;
    case DBTYPE_DBTIMESTAMP:  return sizeof(DBTIMESTAMP);
    case DBTYPE_GUID:         return sizeof(GUID);
    case DBTYPE_DECIMAL:      return sizeof(DECIMAL);
    case DBTYPE_NUMERIC:      return sizeof(DB_NUMERIC);
    case DBTYPE_HCHAPTER:     return sizeof(HCHAPTER);
    default: return 2048;
    }
}

/* The bytes a provider writes for a natively bound column: fixed sizes for fixed types, the column's own
 * reported size for the variable-length ones.  msolap reports ulColumnSize as 0xFFFFFFFF ("unlimited") for its
 * string columns, and using that literally produced a 4 GiB binding whose later columns' offsets wrapped (the
 * provider then reported E_BADACCESSOR on those columns) — hence the cap. */
static DBLENGTH native_len( const DBCOLUMNINFO *ci )
{
    return type_len( ci->wType, ci->ulColumnSize );
}

/* --rows N: after a query, print up to N rows of the returned rowset with every column rendered as a string.
 * The probe could already *execute* a statement and report only its HResult, which distinguishes "the engine
 * refused" from "the engine answered" but cannot read an answer - and the answers that matter here are DMVs
 * (`$SYSTEM.TMSCHEMA_PARTITIONS`, `$SYSTEM.TMSCHEMA_EXPRESSIONS`), where the model's partition sources live.
 * Every column is bound as DBTYPE_WSTR so the provider performs the conversion. */
static void dump_rowset( IRowset *rs, int max_rows )
{
    IColumnsInfo *ci = NULL;
    DBCOLUMNINFO *info = NULL;
    OLECHAR *names = NULL;
    DBORDINAL ncols = 0, i;
    IAccessor *acc = NULL;
    HACCESSOR hacc = NULL;
    DBBINDING *bind = NULL;
    DBBINDSTATUS *stat = NULL;
    DBLENGTH rowlen = 0;
    char *buf = NULL;
    HROW *prows_held = NULL;
    DBCOUNTITEM have = 0, next = 0;
    int r, printed = 0;

    if (FAILED(IRowset_QueryInterface( rs, &IID_IColumnsInfo, (void **)&ci )) || !ci) {
        printf( "  (rowset exposes no IColumnsInfo - cannot read the answer)\n" );
        fflush( stdout );
        return;
    }
    if (FAILED(IColumnsInfo_GetColumnInfo( ci, &ncols, &info, &names )) || !ncols) {
        printf( "  (IColumnsInfo::GetColumnInfo failed or returned no columns)\n" );
        goto done;
    }
    printf( "  columns:" );
    for (i = 0; i < ncols; i++) printf( " %ls", info[i].pwszName ? info[i].pwszName : L"?" );
    printf( "\n" );
    if (g_columns) {
        for (i = 0; i < ncols; i++)
            printf( "  column[%lu] name=%ls wType=0x%04X size=%lu prec=%u scale=%u flags=0x%08lX%s\n",
                    (unsigned long)info[i].iOrdinal, info[i].pwszName ? info[i].pwszName : L"?",
                    (unsigned)info[i].wType, (unsigned long)info[i].ulColumnSize,
                    (unsigned)info[i].bPrecision, (unsigned)info[i].bScale,
                    (unsigned long)info[i].dwFlags,
                    info[i].wType == DBTYPE_HCHAPTER
                        ? "   <-- DBTYPE_HCHAPTER (the type DataReader.GetChildReader serves)" : "" );
    }

    bind = (DBBINDING *)calloc( ncols, sizeof(*bind) );
    stat = (DBBINDSTATUS *)calloc( ncols, sizeof(*stat) );
    if (!bind || !stat) goto done;

    for (i = 0; i < ncols; i++) {
        bind[i].iOrdinal    = info[i].iOrdinal;
        bind[i].obValue     = rowlen + offsetof( DBBINDING, obValue );   /* placeholder, fixed up below */
        bind[i].obLength    = 0;
        bind[i].obStatus    = 0;
        bind[i].pTypeInfo   = NULL;
        bind[i].pObject     = NULL;
        bind[i].pBindExt    = NULL;
        {
            int ord = (int)info[i].iOrdinal;
            int bound = 1;
            if (g_skip_col && g_skip_col == ord) bound = 0;
            if (g_only_col && g_only_col != ord) bound = 0;
            if (!bound) {
                /* A column bound for status only is legal (DBPART_STATUS without DBPART_VALUE): the provider
                 * must not try to produce a value for it, which is how a single column is excluded from the
                 * accessor when bisecting a GetData the provider rejects. */
                bind[i].dwPart     = DBPART_STATUS;
                bind[i].cbMaxLen   = 0;
                bind[i].wType      = DBTYPE_EMPTY;
                bind[i].obValue    = 0;
                bind[i].obLength   = 0;
                bind[i].obStatus   = rowlen; rowlen += sizeof(DBSTATUS);
                continue;
            }
        }
        bind[i].dwPart      = DBPART_VALUE | DBPART_LENGTH | DBPART_STATUS;
        bind[i].dwMemOwner  = DBMEMOWNER_CLIENTOWNED;
        bind[i].eParamIO    = DBPARAMIO_NOTPARAM;
        bind[i].wType       = g_force_type ? (WORD)g_force_type
                            : (g_native ? (info[i].wType & ~DBTYPE_BYREF) : DBTYPE_WSTR);
        bind[i].cbMaxLen    = g_big_buffers ? 2048
                            : (g_force_type ? type_len( (WORD)g_force_type, info[i].ulColumnSize )
                                            : (g_native ? native_len( &info[i] ) : 2048));
        bind[i].dwFlags     = 0;
        bind[i].bPrecision  = g_native ? info[i].bPrecision : 0;
        bind[i].bScale      = g_native ? info[i].bScale : 0;
        bind[i].obValue     = rowlen;
        rowlen += bind[i].cbMaxLen;
        bind[i].obLength    = rowlen;  rowlen += sizeof(DBLENGTH);
        bind[i].obStatus    = rowlen;  rowlen += sizeof(DBSTATUS);
    }
    if (FAILED(IRowset_QueryInterface( rs, &IID_IAccessor, (void **)&acc )) || !acc) {
        printf( "  (rowset exposes no IAccessor)\n" );
        goto done;
    }
    if (FAILED(IAccessor_CreateAccessor( acc, DBACCESSOR_ROWDATA, ncols, bind, rowlen, &hacc, stat ))) {
        printf( "  (CreateAccessor failed)\n" );
        goto done;
    }
    buf = (char *)malloc( rowlen );
    if (!buf) goto done;

    for (r = 0; r < max_rows; r++) {
        HROW *prows = NULL;                 /* GetNextRows returns an array of handles, not one */
        DBCOUNTITEM got = 0;
        HRESULT hr;
        /* ATL reads every row of a fetched batch before calling GetNextRows again (`m_nRowsPerFetch`
         * rows at a time), so this does too: a fresh GetNextRows only when the batch is exhausted. */
        if (next >= have) {
            if (prows_held) { IRowset_ReleaseRows( rs, have, prows_held, NULL, NULL, NULL ); prows_held = NULL; }
            hr = IRowset_GetNextRows( rs, DB_NULL_HCHAPTER, 0, g_fetch, &got, &prows );
            if (FAILED(hr) || got == 0 || !prows) {
                printf( "  IRowset::GetNextRows(cRows=%d) -> hr=0x%08lX rows=%lu\n",
                        g_fetch, (unsigned long)hr, (unsigned long)got );
                dump_error_records( "GetNextRows" );   /* the call the app's wrapper fails on */
                break;
            }
            prows_held = prows;
            have = got;
            next = 0;
        }
        memset( buf, 0, rowlen );
        /* Relay-visible bracket around the failing call: with WINEDEBUG=+relay the provider's own calls to
         * Wine DLLs appear between these two KERNEL32.OutputDebugStringA calls, which is what makes the
         * GetData window extractable from a 1M-line relay log (docs/I8_BINDING_FIX.md). */
        OutputDebugStringA( "@@GD-START" );
        hr = IRowset_GetData( rs, prows_held[next], hacc, buf );   /* the other call inside the wrapper's MoveNext */
        OutputDebugStringA( "@@GD-END" );
        next++;
        printf( "  IRowset::GetData -> hr=0x%08lX%s\n", (unsigned long)hr,
                FAILED(hr) ? "  (FAILED)" : (hr == S_OK ? "" : "  (success code)") );
        if (FAILED(hr)) {
            dump_error_records( "GetData" );
            break;
        }
        printf( "  row[%d]:", r );
        for (i = 0; i < ncols; i++) {
            DBSTATUS st = *(DBSTATUS *)( buf + bind[i].obStatus );
            DBLENGTH len = *(DBLENGTH *)( buf + bind[i].obLength );
            char *v = buf + bind[i].obValue;
            printf( " %ls=", info[i].pwszName ? info[i].pwszName : L"?" );
            if (!(bind[i].dwPart & DBPART_VALUE)) printf( "(not bound)" );
            else if (st != DBSTATUS_S_OK && st != DBSTATUS_S_ISNULL && st != DBSTATUS_S_TRUNCATED)
                printf( "<%s(0x%08lX) len=%lu>", status_name( st ), (unsigned long)st, (unsigned long)len );
            else if (st == DBSTATUS_S_ISNULL)
                printf( "(null)" );
            else {
                if (g_status) printf( "[%s]", status_name( st ) );
                if (bind[i].wType == DBTYPE_WSTR)      printf( "%ls", (const WCHAR *)v );
                else if (bind[i].wType == DBTYPE_STR)  printf( "%s", v );
                else if (bind[i].wType == DBTYPE_I4)   printf( "%ld", (long)*(const INT32 *)v );
                else if (bind[i].wType == DBTYPE_UI4)  printf( "%lu", (unsigned long)*(const UINT32 *)v );
                else if (bind[i].wType == DBTYPE_I8)   printf( "%lld", (long long)*(const INT64 *)v );
                else if (bind[i].wType == DBTYPE_UI8)  printf( "%llu", (unsigned long long)*(const UINT64 *)v );
                else if (bind[i].wType == DBTYPE_I2)   printf( "%d", (int)*(const INT16 *)v );
                else if (bind[i].wType == DBTYPE_UI2)  printf( "%u", (unsigned)*(const UINT16 *)v );
                else if (bind[i].wType == DBTYPE_R8)   printf( "%.10g", *(const double *)v );
                else if (bind[i].wType == DBTYPE_R4)   printf( "%.6g", (double)*(const float *)v );
                else if (bind[i].wType == DBTYPE_BOOL) printf( "%d", (int)*(const VARIANT_BOOL *)v );
                else if (bind[i].wType == DBTYPE_HCHAPTER)
                    printf( "HCHAPTER(0x%llX)", (unsigned long long)*(const HCHAPTER *)v );
                else printf( "<type 0x%04X len=%lu>", bind[i].wType, (unsigned long)len );
            }
        }
        printf( "\n" );
        printed++;
    }
    printf( "  rows printed: %d\n", printed );

done:
    if (prows_held) IRowset_ReleaseRows( rs, have, prows_held, NULL, NULL, NULL );
    if (buf) free( buf );
    if (acc) IAccessor_Release( acc );   /* releasing the accessor's owner releases the rowset's accessor */
    (void)hacc;
    if (bind) free( bind );
    if (stat) free( stat );
    if (ci) IColumnsInfo_Release( ci );
    fflush( stdout );
}

/* --parent: the chapter read, isolated.  `DataReader.GetChildReader` query-interfaces the rowset the command
 * returned for IParentRowset and asks *it* for each chapter's rowset, so the thing to measure is whether the
 * provider exposes IParentRowset on a rowset at all, and if it does, whether GetChildRowset answers. */
static void walk_parent( IRowset *rs, int max_rows )
{
    IParentRowset *pr = NULL;
    IColumnsInfo *ci = NULL;
    DBORDINAL ncols = 0, i;
    DBCOLUMNINFO *info = NULL;
    OLECHAR *names = NULL;
    int ord;

    /* IParentRowset::GetChildRowset's second parameter is the *ordinal of the chapter column*, not an index
     * into a list of chapters, so every ordinal a caller could plausibly pass is tried: 0 (what a 0-based
     * managed column index becomes), then 1..ncols (the real ordinals).  DB_E_BADCHAPTER on the others is
     * expected and is only noise. */
    if (SUCCEEDED(IRowset_QueryInterface( rs, &IID_IColumnsInfo, (void **)&ci )) && ci) {
        if (SUCCEEDED(IColumnsInfo_GetColumnInfo( ci, &ncols, &info, &names ))) {
            printf( "  parent rowset columns:" );
            for (i = 0; i < ncols; i++)
                printf( " [%lu]%ls:0x%04X", (unsigned long)info[i].iOrdinal,
                        info[i].pwszName ? info[i].pwszName : L"?", (unsigned)info[i].wType );
            printf( "\n" );
        }
        IColumnsInfo_Release( ci );
    }

    if (SUCCEEDED(IRowset_QueryInterface( rs, &IID_IParentRowset, (void **)&pr )) && pr) {
        printf( "  rowset IS IParentRowset -> walking chapter ordinals 0..%lu\n", (unsigned long)ncols + 1 );
        for (ord = 0; ord <= (int)ncols + 1; ord++) {
            IRowset *child = NULL;
            HRESULT hr = IParentRowset_GetChildRowset( pr, NULL, (DBORDINAL)ord, &IID_IRowset,
                                                       (IUnknown **)&child );
            printf( "  chapterord[%d] IParentRowset::GetChildRowset(ordinal=%d) -> hr=0x%08lX%s\n", ord, ord,
                    (unsigned long)hr, child ? "" : " (no rowset)" );
            if (SUCCEEDED(hr) && child) {
                if (max_rows > 0) dump_rowset( child, max_rows );
                IRowset_Release( child );
            } else {
                dump_error_records( "GetChildRowset" );
            }
        }
        IParentRowset_Release( pr );
    } else {
        printf( "  (rowset exposes no IParentRowset)\n" );
    }
    fflush( stdout );
}

/* --children: walk the result the way the app's own wrapper does, because the visual's failure is not in the query
 * but in reading parts of its result back (docs/DATA_FETCH_ERROR.md §7).  The chart's DataShape is the only one with
 * a secondary hierarchy, i.e. the only read that goes through msolap's chapter rowset path, and it fails with
 * DB_E_ERRORSINCOMMAND while the plain rowset path reads fine.  Two late-bound reads are reproduced here:
 * IParentRowset::GetChildRowset for each chapter, and IMultipleResults::GetResult for each further result set. */
static void walk_result( IUnknown *result, int max_rows )
{
    IMultipleResults *mr = NULL;
    IParentRowset *pr = NULL;
    IRowset *rs = NULL;
    int idx, r;
    int rows = (max_rows > 3) ? 3 : max_rows;

    if (SUCCEEDED(IUnknown_QueryInterface( result, &IID_IParentRowset, (void **)&pr )) && pr) {
        for (idx = 0; idx < 8; idx++) {
            HRESULT hr;
            rs = NULL;
            hr = IParentRowset_GetChildRowset( pr, NULL, idx, &IID_IRowset, (IUnknown **)&rs );
            printf( "  child[%d] IParentRowset::GetChildRowset -> hr=0x%08lX%s\n", idx, (unsigned long)hr,
                    rs ? "" : " (no rowset)" );
            if (FAILED(hr) || !rs) { dump_error_records( "GetChildRowset" ); break; }
            if (rows > 0) dump_rowset( rs, rows );
            IRowset_Release( rs );
        }
        IParentRowset_Release( pr );
    } else {
        printf( "  (result exposes no IParentRowset)\n" );
    }

    if (SUCCEEDED(IUnknown_QueryInterface( result, &IID_IMultipleResults, (void **)&mr )) && mr) {
        for (r = 0; r < 4; r++) {
            DBROWCOUNT affected = 0;
            HRESULT hr;
            rs = NULL;
            hr = IMultipleResults_GetResult( mr, NULL, DBRESULTFLAG_DEFAULT, &IID_IRowset, &affected,
                                            (IUnknown **)&rs );
            printf( "  next-result[%d] IMultipleResults::GetResult -> hr=0x%08lX%s\n", r, (unsigned long)hr,
                    rs ? "" : " (no rowset)" );
            if (FAILED(hr) || !rs) { dump_error_records( "GetResult" ); break; }
            walk_parent( rs, rows );          /* a result rowset is where chapters would live */
            if (rows > 0) dump_rowset( rs, rows );
            IRowset_Release( rs );
        }
        IMultipleResults_Release( mr );
    } else {
        printf( "  (result exposes no IMultipleResults)\n" );
    }
    fflush( stdout );
}

static void dump_error_info(void)
{
    IErrorInfo *ei = NULL;
    const char *no = "No OLE DB Error Information found.";
    HRESULT hr = GetErrorInfo(0, &ei);
    if (FAILED(hr) || !ei) {
        printf("  GetErrorInfo                              no error info (hr=0x%08lX) -- %s\n",
               (unsigned long)hr, no);
        return;
    }
    BSTR desc = NULL, src = NULL;
    if (SUCCEEDED(IErrorInfo_GetDescription(ei, &desc)) && desc) {
        printf("  IErrorInfo::GetDescription                \"");
        print_bstr(desc);
        printf("\"\n");
    }
    if (SUCCEEDED(IErrorInfo_GetSource(ei, &src)) && src) {
        printf("  IErrorInfo::GetSource                     \"");
        print_bstr(src);
        printf("\"\n");
    }
    if (desc) SysFreeString(desc);
    if (src) SysFreeString(src);
    IErrorInfo_Release(ei);
}


/* ------------------------------------------------------------------------------------------------------------
 * Targeted IAT hooks.
 *
 * msolap.dll imports GetLastError, SetLastError and HeapValidate from KERNEL32 by name, so the exact slots can
 * be rewritten in the loaded image.  That turns "the provider reports ERROR_INVALID_FUNCTION" into "this call,
 * from this offset in msolap.dll, produced it" without needing symbols for a 12 MB Microsoft binary.
 * ----------------------------------------------------------------------------------------------- */
static void show_backtrace(const char *why);

typedef void *(*iat_hook_fn)(void);
static void **find_iat_slot(HMODULE mod, const char *dll, const char *func)
{
    BYTE *base = (BYTE *)mod;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
    IMAGE_IMPORT_DESCRIPTOR *imp = (IMAGE_IMPORT_DESCRIPTOR *)
        (base + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    for (; imp->Name; imp++) {
        const char *mod_name = (const char *)(base + imp->Name);
        IMAGE_THUNK_DATA *thunk, *orig;
        if (_stricmp(mod_name, dll)) continue;
        thunk = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        orig = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
        for (; orig->u1.AddressOfData; thunk++, orig++) {
            IMAGE_IMPORT_BY_NAME *ibn;
            if (orig->u1.Ordinal & IMAGE_ORDINAL_FLAG) continue;
            ibn = (IMAGE_IMPORT_BY_NAME *)(base + orig->u1.AddressOfData);
            if (!strcmp((const char *)ibn->Name, func)) return (void **)&thunk->u1.Function;
        }
    }
    return NULL;
}

static void patch_iat(HMODULE mod, const char *dll, const char *func, void *hook, void **orig)
{
    void **slot = find_iat_slot(mod, dll, func);
    if (!slot) { printf("  [hook] (no IAT slot for %s!%s)\n", dll, func); return; }
    *orig = *slot;
    DWORD old;
    VirtualProtect(slot, sizeof(void *), PAGE_READWRITE, &old);
    *slot = hook;
    VirtualProtect(slot, sizeof(void *), old, &old);
}

static BOOL (WINAPI *orig_HeapValidate)(HANDLE, DWORD, LPCVOID);
static BOOL WINAPI hook_HeapValidate(HANDLE heap, DWORD flags, LPCVOID ptr)
{
    BOOL r = orig_HeapValidate(heap, flags, ptr);
    if (!r) {
        char msg[160];
        snprintf(msg, sizeof(msg), "HeapValidate(heap=%p, flags=%lu, ptr=%p) -> FALSE, GetLastError=%lu",
                 (void *)heap, (unsigned long)flags, ptr, (unsigned long)GetLastError());
        show_backtrace(msg);
    }
    return r;
}

static DWORD (WINAPI *orig_GetLastError)(void);
static DWORD WINAPI hook_GetLastError(void)
{
    DWORD e = orig_GetLastError();
    if (e) {
        char msg[96];
        snprintf(msg, sizeof(msg), "GetLastError() -> %lu (msolap read this)", (unsigned long)e);
        show_backtrace(msg);
    }
    return e;
}

static VOID (WINAPI *orig_SetLastError)(DWORD);
static VOID WINAPI hook_SetLastError(DWORD err)
{
    if (err == 1) show_backtrace("SetLastError(1) == ERROR_INVALID_FUNCTION");
    orig_SetLastError(err);
}

static void install_iat_hooks(HMODULE mod)
{
    patch_iat(mod, "KERNEL32.dll", "HeapValidate", (void *)hook_HeapValidate, (void **)&orig_HeapValidate);
    patch_iat(mod, "KERNEL32.dll", "GetLastError", (void *)hook_GetLastError, (void **)&orig_GetLastError);
    patch_iat(mod, "KERNEL32.dll", "SetLastError", (void *)hook_SetLastError, (void **)&orig_SetLastError);
    printf("  [hook] HeapValidate/GetLastError/SetLastError hooked in msolap.dll\n");
    fflush(stdout);
}


/* ------------------------------------------------------------------------------------------------------------
 * SSPI function-table hook, addressed by name.
 *
 * msolap.dll resolves secur32's InitSecurityInterfaceW *dynamically* (LoadLibrary + GetProcAddress, so there is no
 * import slot to patch) and then drives the whole authentication through the returned function table, i.e. through
 * indirect calls that neither the import hook above nor Wine's relay can see.  The only way to learn what the
 * provider's SSPI client is told is therefore to hand it a copy of that table whose entries are replaced, and to
 * replace them *by name*: each table word that is exactly the address secur32 exports under a known name gets the
 * wrapper declared for that same prototype.  Matching on the address (not on a fixed index) means a table layout
 * difference leaves the copy intact instead of mis-calling, and a name secur32 does not export is skipped rather
 * than matching the NULL entries.
 * ----------------------------------------------------------------------------------------------- */
#define SSPI_MAX_WRAP 32
static struct { const char *name; void *real; void *wrap; } g_wrap[SSPI_MAX_WRAP];
static int g_wrap_n, g_sspi_calls;
static int g_spnego;        /* --spnego: report Wine's NTLM flow in the shape Windows' SPNEGO flow has */
static int g_spnego_pending;

static SECURITY_STATUS (SEC_ENTRY *orig_ACH)( SEC_WCHAR *, SEC_WCHAR *, ULONG, PVOID, PVOID, PVOID, PVOID,
                                              PCredHandle, PTimeStamp );
static SECURITY_STATUS (SEC_ENTRY *orig_ISC)( PCredHandle, PCtxtHandle, SEC_WCHAR *, ULONG, ULONG, ULONG,
                                              PSecBufferDesc, ULONG, PCtxtHandle, PSecBufferDesc, PULONG, PTimeStamp );
static SECURITY_STATUS (SEC_ENTRY *orig_ASC)( PCredHandle, PCtxtHandle, PSecBufferDesc, ULONG, ULONG,
                                              PCtxtHandle, PSecBufferDesc, PULONG, PTimeStamp );
static SECURITY_STATUS (SEC_ENTRY *orig_QCA)( PCtxtHandle, ULONG, PVOID );
static SECURITY_STATUS (SEC_ENTRY *orig_QCP)( PCtxtHandle, ULONG, PVOID );
static SECURITY_STATUS (SEC_ENTRY *orig_DSC)( PCtxtHandle );
static SECURITY_STATUS (SEC_ENTRY *orig_FCH)( PCredHandle );
static SECURITY_STATUS (SEC_ENTRY *orig_ENUM)( ULONG *, PSecPkgInfoW * );
static SECURITY_STATUS (SEC_ENTRY *orig_QSPI)( SEC_WCHAR *, PSecPkgInfoW * );
static SECURITY_STATUS (SEC_ENTRY *orig_FCB)( PVOID );

static void token_summary( const char *what, SecBuffer *buf )
{
    const unsigned char *p = buf->pvBuffer;
    char sig[12];
    unsigned i;
    if (!p || !buf->cbBuffer) { printf("  [sspi] %s: %lu bytes (empty)\n", what, (unsigned long)buf->cbBuffer); return; }
    for (i = 0; i < 11 && i < buf->cbBuffer; i++) sig[i] = (p[i] >= 32 && p[i] < 127) ? p[i] : '.';
    sig[i] = 0;
    /* The first 16 bytes in hex as well as the printable signature: the *framing* of a token (ASN.1
     * [APPLICATION 0] 0x60 on the SPNEGO NegTokenInit, the context tag for NegTokenResp, the OID
     * 1.3.6.1.5.5.2 of the SPNEGO mech) is what a gate can compare across platforms, because the *inner* mech
     * tokens legitimately differ in length between Wine and Windows. */
    printf("  [sspi] %s: %lu bytes  [%s]  first=%02x%02x %02x%02x  hex=", what, (unsigned long)buf->cbBuffer, sig,
           p[0], p[1], p[8], p[9]);
    for (i = 0; i < 16 && i < buf->cbBuffer; i++) printf("%02x", p[i]);
    printf("\n");
}

/* AcquireCredentialsHandleW's parameters are (pszPrincipal, pszPackage, fCredentialUse, pvLogonID, pAuthData,
 * pGetKeyFn, pvGetKeyArgument, phCredential, ptsExpiry) — the *second* argument is the package, so both must be
 * printed: whether the provider asks for a package by name or leaves the choice to the system is the fact that
 * decides whether the two platforms' flows are comparable. */
static SECURITY_STATUS SEC_ENTRY log_ACH( SEC_WCHAR *principal, SEC_WCHAR *package, ULONG usage, PVOID logonid,
                                          PVOID authdata, PVOID getkey, PVOID getkeyarg,
                                          PCredHandle cred, PTimeStamp exp )
{
    SECURITY_STATUS s = orig_ACH( principal, package, usage, logonid, authdata, getkey, getkeyarg, cred, exp );
    printf( "  [sspi] AcquireCredentialsHandleW principal=%ls package=%ls usage=0x%lx authdata=%p -> status=0x%08lX\n",
            principal ? principal : L"(null)", package ? package : L"(NULL)", (unsigned long)usage, authdata,
            (unsigned long)s );
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_ISC( PCredHandle hcred, PCtxtHandle hctx, SEC_WCHAR *target, ULONG req,
                                          ULONG r1, ULONG rep, PSecBufferDesc in, ULONG r2, PCtxtHandle newctx,
                                          PSecBufferDesc out, PULONG attr, PTimeStamp exp )
{
    SECURITY_STATUS s;
    int n = ++g_sspi_calls;
    if (g_tracer_late && !g_tracer_installed && g_dbinit_late)
        install_tracer( g_dbinit_late );            /* the provider is inside Initialize() here; its queue exists */
    printf( "  [sspi] InitializeSecurityContextW #%d target=%ls flags=0x%lx ctx=%s input=%s\n", n,
            target ? target : L"(null)", (unsigned long)req, hctx ? "continue" : "new",
            ( in && in->cBuffers ) ? "yes" : "no" );
    if (in && in->cBuffers && in->pBuffers) token_summary( "  in ", &in->pBuffers[0] );
    if (out && out->cBuffers && out->pBuffers)
        printf( "  [sspi]   out buf before: type=%lu size=%lu\n", (unsigned long)out->pBuffers[0].BufferType,
                (unsigned long)out->pBuffers[0].cbBuffer );
    s = orig_ISC( hcred, hctx, target, req, r1, rep, in, r2, newctx, out, attr, exp );

    /* --spnego: give Wine's raw-NTLM client context the *shape* Windows' Negotiate/SPNEGO context has, so the
     * provider's loop sees what it sees on Windows: a token to send at the round where Wine says "complete", and a
     * final call that completes with no token.  This is a probe-side emulation used to test whether that shape is
     * what the provider needs — it does not change Wine itself. */
    if (g_spnego) {
        ULONG outlen = ( out && out->cBuffers && out->pBuffers ) ? out->pBuffers[0].cbBuffer : 0;
        if (s == SEC_E_OK && outlen) {
            printf( "  [sspi]   --spnego: SEC_E_OK with a %lu-byte token -> reporting SEC_I_CONTINUE_NEEDED\n",
                    (unsigned long)outlen );
            g_spnego_pending = 1;
            s = SEC_I_CONTINUE_NEEDED;
        }
        else if (g_spnego_pending) {
            printf( "  [sspi]   --spnego: completion call (status was 0x%08lX) -> reporting SEC_E_OK, no token\n",
                    (unsigned long)s );
            g_spnego_pending = 0;
            if (out && out->cBuffers && out->pBuffers) {
                out->pBuffers[0].cbBuffer = 0;
                out->pBuffers[0].BufferType = SECBUFFER_TOKEN;
            }
            if (attr) *attr = 0x1001e;
            s = SEC_E_OK;
        }
    }

    printf( "  [sspi] InitializeSecurityContextW #%d -> status=0x%08lX attr=0x%lx\n", n, (unsigned long)s,
            (unsigned long)( attr ? *attr : 0 ) );
    if (out && out->cBuffers && out->pBuffers) token_summary( "  out", &out->pBuffers[0] );
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_ASC( PCredHandle hcred, PCtxtHandle hctx, PSecBufferDesc in, ULONG req,
                                          ULONG targ, PCtxtHandle newctx, PSecBufferDesc out, PULONG attr,
                                          PTimeStamp exp )
{
    SECURITY_STATUS s = orig_ASC( hcred, hctx, in, req, targ, newctx, out, attr, exp );
    printf( "  [sspi] AcceptSecurityContext flags=0x%lx -> status=0x%08lX\n", (unsigned long)req,
            (unsigned long)s );
    fflush( stdout );
    return s;
}

/* --pkgname=NTLM: report what Windows reports for the same query.  On Windows, QueryContextAttributes on a
 * Negotiate context with SECPKG_ATTR_PACKAGE_INFO answers with the *negotiated* mechanism's info ("NTLM"), and the
 * provider opens the connection successfully with that answer; Wine's patched Negotiate answers "Negotiate"
 * instead.  Overriding the answer here asks the provider the same question the Wine-vs-Windows differential asks:
 * is *this* the call whose answer it rejects? */
static int g_pkg_name;
static WCHAR g_pkg_name_w[64] = L"NTLM";
static WCHAR g_pkg_comment_w[64] = L"NTLM Security Package";

/* The provider's last two SSPI calls before it gives up are QueryContextAttributes SIZES and PACKAGE_INFO, so the
 * payloads matter as much as the status: a returned SecPkgInfoW whose strings the caller cannot read (or a buffer
 * its own FreeContextBuffer cannot free) is the kind of difference that is invisible in a status-only log. */
static SECURITY_STATUS SEC_ENTRY log_QCA( PCtxtHandle hctx, ULONG attr, PVOID buf )
{
    SECURITY_STATUS s = orig_QCA( hctx, attr, buf );
    printf( "  [sspi] QueryContextAttributes ctx=%p attr=%lu -> status=0x%08lX\n", (void *)hctx,
            (unsigned long)attr, (unsigned long)s );
    if ( SUCCEEDED( s ) && buf ) {
        if (attr == SECPKG_ATTR_SIZES) {
            SecPkgContext_Sizes *sz = (SecPkgContext_Sizes *)buf;
            printf( "  [sspi]   SIZES maxToken=%lu maxSignature=%lu blockSize=%lu securityTrailer=%lu\n",
                    (unsigned long)sz->cbMaxToken, (unsigned long)sz->cbMaxSignature,
                    (unsigned long)sz->cbBlockSize, (unsigned long)sz->cbSecurityTrailer );
        }
        else if (attr == SECPKG_ATTR_PACKAGE_INFO) {
            SecPkgContext_PackageInfoW *pi = (SecPkgContext_PackageInfoW *)buf;
            SecPkgInfoW *info = pi->PackageInfo;
            printf( "  [sspi]   PACKAGE_INFO ptr=%p\n", (void *)info );
            if (info) {
                printf( "  [sspi]   PACKAGE_INFO name=\"%ls\" caps=0x%lx maxToken=%lu comment=\"%ls\"\n",
                        info->Name ? info->Name : L"(null)", (unsigned long)info->fCapabilities,
                        (unsigned long)info->cbMaxToken, info->Comment ? info->Comment : L"(null)" );
                printf( "  [sspi]   PACKAGE_INFO name ptr=%p (HeapValidate=%s)\n", (void *)info->Name,
                        HeapValidate( GetProcessHeap(), 0, info->Name ) ? "process heap" : "not the process heap" );
                if (g_pkg_name) {
                    /* the peer's struct is in the buffer the package allocated for the caller, so pointing its two
                     * string fields at our own static strings is enough for the provider to read the Windows answer */
                    info->Name = g_pkg_name_w;
                    info->Comment = g_pkg_comment_w;
                    printf( "  [sspi]   --pkgname: reporting name=\"%ls\" to the provider (Windows reference)\n",
                            g_pkg_name_w );
                }
            }
        }
        else if (attr == SECPKG_ATTR_NEGOTIATION_INFO) {
            SecPkgContext_NegotiationInfoW *ni = (SecPkgContext_NegotiationInfoW *)buf;
            printf( "  [sspi]   NEGOTIATION_INFO state=%lu packageInfo=%p\n", (unsigned long)ni->NegotiationState,
                    (void *)ni->PackageInfo );
        }
    }
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_QCP( PCtxtHandle hctx, ULONG attr, PVOID buf )
{
    SECURITY_STATUS s = orig_QCP( hctx, attr, buf );
    printf( "  [sspi] QueryContextAttributesEx ctx=%p attr=%lu -> status=0x%08lX\n", (void *)hctx,
            (unsigned long)attr, (unsigned long)s );
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_DSC( PCtxtHandle hctx )
{
    SECURITY_STATUS s = orig_DSC( hctx );
    printf( "  [sspi] DeleteSecurityContext ctx=%p -> status=0x%08lX\n", (void *)hctx, (unsigned long)s );
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_FCH( PCredHandle hcred )
{
    SECURITY_STATUS s = orig_FCH( hcred );
    printf( "  [sspi] FreeCredentialsHandle -> status=0x%08lX\n", (unsigned long)s );
    fflush( stdout );
    return s;
}

/* The provider walks the package list looking for a name (relay shows it comparing L"NTLM" against every entry),
 * so dump what secur32 reports: on Windows this list is the OS's, under Wine it is the builtin's. */
static SECURITY_STATUS SEC_ENTRY log_ENUM( ULONG *count, PSecPkgInfoW *info )
{
    SECURITY_STATUS s = orig_ENUM( count, info );
    ULONG i;
    printf( "  [sspi] EnumerateSecurityPackagesW -> status=0x%08lX count=%lu table=%p\n", (unsigned long)s,
            (unsigned long)( count ? *count : 0 ), (void *)( info ? *info : NULL ) );
    if ( SUCCEEDED( s ) && info && *info )
        for (i = 0; i < *count; i++)
            printf( "  [sspi]   pkg[%lu] \"%ls\" caps=0x%lx maxToken=%lu\n", (unsigned long)i,
                    (*info)[i].Name ? (*info)[i].Name : L"(null)", (unsigned long)(*info)[i].fCapabilities,
                    (unsigned long)(*info)[i].cbMaxToken );
    fflush( stdout );
    return s;
}

static SECURITY_STATUS SEC_ENTRY log_QSPI( SEC_WCHAR *name, PSecPkgInfoW *info )
{
    SECURITY_STATUS s = orig_QSPI( name, info );
    printf( "  [sspi] QuerySecurityPackageInfoW \"%ls\" -> status=0x%08lX%s\n", name ? name : L"(null)",
            (unsigned long)s, ( SUCCEEDED( s ) && info && *info ) ? "" : " (no info)" );
    if ( SUCCEEDED( s ) && info && *info )
        printf( "  [sspi]   name=\"%ls\" caps=0x%lx maxToken=%lu\n",
                (*info)[0].Name ? (*info)[0].Name : L"(null)", (unsigned long)(*info)[0].fCapabilities,
                (unsigned long)(*info)[0].cbMaxToken );
    fflush( stdout );
    return s;
}

/* Wine's FreeContextBuffer returns LsaFreeReturnBuffer()'s value for a buffer that is not on the process heap,
 * and that function returns VirtualFree()'s BOOL as an NTSTATUS -- so a *successful* free reports
 * SEC_E_INVALID_HANDLE (1).  HeapValidate() shows which allocator the buffer belongs to, and --freeok asks the
 * provider-side question directly: does Initialize() succeed if FreeContextBuffer reports SEC_E_OK the way
 * Windows does? */
static int g_free_ok;

static SECURITY_STATUS (SEC_ENTRY *orig_T0)( PCtxtHandle h, PSecBufferDesc b );
static SECURITY_STATUS SEC_ENTRY wrap_T0( PCtxtHandle h, PSecBufferDesc b )
{
    SECURITY_STATUS st = orig_T0( h, b );
    printf( "  [sspi] CompleteAuthToken (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T1)( PCtxtHandle h, PSecBufferDesc b );
static SECURITY_STATUS SEC_ENTRY wrap_T1( PCtxtHandle h, PSecBufferDesc b )
{
    SECURITY_STATUS st = orig_T1( h, b );
    printf( "  [sspi] ApplyControlToken (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T2)( PCtxtHandle h, ULONG qop, PSecBufferDesc b, ULONG seq );
static SECURITY_STATUS SEC_ENTRY wrap_T2( PCtxtHandle h, ULONG qop, PSecBufferDesc b, ULONG seq )
{
    SECURITY_STATUS st = orig_T2( h, qop, b, seq );
    printf( "  [sspi] MakeSignature (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T3)( PCtxtHandle h, PSecBufferDesc b, ULONG seq, PULONG qop );
static SECURITY_STATUS SEC_ENTRY wrap_T3( PCtxtHandle h, PSecBufferDesc b, ULONG seq, PULONG qop )
{
    SECURITY_STATUS st = orig_T3( h, b, seq, qop );
    printf( "  [sspi] VerifySignature (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T4)( PCtxtHandle h, ULONG qop, PSecBufferDesc b, ULONG seq );
static SECURITY_STATUS SEC_ENTRY wrap_T4( PCtxtHandle h, ULONG qop, PSecBufferDesc b, ULONG seq )
{
    SECURITY_STATUS st = orig_T4( h, qop, b, seq );
    printf( "  [sspi] EncryptMessage (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T5)( PCtxtHandle h, PSecBufferDesc b, ULONG seq, PULONG qop );
static SECURITY_STATUS SEC_ENTRY wrap_T5( PCtxtHandle h, PSecBufferDesc b, ULONG seq, PULONG qop )
{
    SECURITY_STATUS st = orig_T5( h, b, seq, qop );
    printf( "  [sspi] DecryptMessage (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T6)( PCredHandle c, ULONG a, PVOID b );
static SECURITY_STATUS SEC_ENTRY wrap_T6( PCredHandle c, ULONG a, PVOID b )
{
    SECURITY_STATUS st = orig_T6( c, a, b );
    printf( "  [sspi] QueryCredentialsAttributesW (first=%p) -> status=0x%08lX\n", (void *)c, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T7)( PCredHandle c, ULONG a, PVOID b );
static SECURITY_STATUS SEC_ENTRY wrap_T7( PCredHandle c, ULONG a, PVOID b )
{
    SECURITY_STATUS st = orig_T7( c, a, b );
    printf( "  [sspi] QueryCredentialsAttributesA (first=%p) -> status=0x%08lX\n", (void *)c, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T8)( PCtxtHandle h, ULONG a, PVOID b, ULONG n );
static SECURITY_STATUS SEC_ENTRY wrap_T8( PCtxtHandle h, ULONG a, PVOID b, ULONG n )
{
    SECURITY_STATUS st = orig_T8( h, a, b, n );
    printf( "  [sspi] SetContextAttributesW (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T9)( PCtxtHandle h );
static SECURITY_STATUS SEC_ENTRY wrap_T9( PCtxtHandle h )
{
    SECURITY_STATUS st = orig_T9( h );
    printf( "  [sspi] ImpersonateSecurityContext (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T10)( PCtxtHandle h );
static SECURITY_STATUS SEC_ENTRY wrap_T10( PCtxtHandle h )
{
    SECURITY_STATUS st = orig_T10( h );
    printf( "  [sspi] RevertSecurityContext (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T11)( PCtxtHandle h, void **tok );
static SECURITY_STATUS SEC_ENTRY wrap_T11( PCtxtHandle h, void **tok )
{
    SECURITY_STATUS st = orig_T11( h, tok );
    printf( "  [sspi] QuerySecurityContextToken (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T12)( PCtxtHandle h, ULONG f, PSecBuffer p, PVOID *x );
static SECURITY_STATUS SEC_ENTRY wrap_T12( PCtxtHandle h, ULONG f, PSecBuffer p, PVOID *x )
{
    SECURITY_STATUS st = orig_T12( h, f, p, x );
    printf( "  [sspi] ExportSecurityContext (first=%p) -> status=0x%08lX\n", (void *)h, (unsigned long)st );
    fflush( stdout );
    return st;
}
static SECURITY_STATUS (SEC_ENTRY *orig_T13)( const SEC_WCHAR *pkg, PSecBuffer p, PVOID *x );
static SECURITY_STATUS SEC_ENTRY wrap_T13( const SEC_WCHAR *pkg, PSecBuffer p, PVOID *x )
{
    SECURITY_STATUS st = orig_T13( pkg, p, x );
    printf( "  [sspi] ImportSecurityContextW (first=%p) -> status=0x%08lX\n", (void *)*pkg, (unsigned long)st );
    fflush( stdout );
    return st;
}

static SECURITY_STATUS SEC_ENTRY log_FCB( PVOID buf )
{
    SECURITY_STATUS s = orig_FCB( buf );
    printf( "  [sspi] FreeContextBuffer(%p) -> status=0x%08lX  (HeapValidate=%s)\n", buf, (unsigned long)s,
            HeapValidate( GetProcessHeap(), 0, buf ) ? "process heap" : "not the process heap" );
    if (g_free_ok && s != SEC_E_OK) {
        printf( "  [sspi]   --freeok: reporting SEC_E_OK to the provider instead of 0x%08lX\n", (unsigned long)s );
        s = SEC_E_OK;
    }
    fflush( stdout );
    return s;
}

/* msolap reaches the SSPI table through Security.dll/secur32's exported InitSecurityInterfaceW.  Hooking
 * GetProcAddress to intercept that resolution *changes the provider's behaviour* (measured: with the hook installed
 * the provider resolves the name earlier and IClassFactory::CreateInstance then fails with its own 0xC1000002), so
 * the interception is done on the function itself instead: the real table is fetched once, a copy with the wrappers
 * is built from it, and the exported function's entry is overwritten with a jump to a replacement that returns the
 * copy.  Nothing else in the provider's world changes -- every GetProcAddress still returns exactly what the
 * module exports. */
static PSecurityFunctionTableW g_sspi_copy;
static int g_sspi_detoured;

static PSecurityFunctionTableW SEC_ENTRY my_ISI( void )
{
    printf( "  [sspi] InitSecurityInterfaceW() called -> inspected table copy %p\n", (void *)g_sspi_copy );
    fflush( stdout );
    return g_sspi_copy;
}

static void detour_function( void *target, void *replacement )
{
    DWORD old;
    BYTE patch[12] = { 0x48, 0xB8 };   /* mov rax, imm64 ; jmp rax  -- the body is not needed any more */
    *(void **)( patch + 2 ) = replacement;
    patch[10] = 0xFF;
    patch[11] = 0xE0;
    if (!VirtualProtect( target, sizeof(patch), PAGE_EXECUTE_READWRITE, &old )) return;
    memcpy( target, patch, sizeof(patch) );
    VirtualProtect( target, sizeof(patch), old, &old );
    FlushInstructionCache( GetCurrentProcess(), target, sizeof(patch) );
}

static FARPROC (WINAPI *orig_GPA)( HMODULE, LPCSTR );
static int g_gpa_log;   /* --gpa: also log every dynamically resolved import (perturbs the provider, so opt-in) */
static FARPROC WINAPI hook_GPA( HMODULE mod, LPCSTR name );

static int build_table_copy( PSecurityFunctionTableW real )
{
    static struct { const char *name; void *wrap; void *real; } want[] = {
        { "AcquireCredentialsHandleW",     (void *)log_ACH,  NULL },
        { "InitializeSecurityContextW",    (void *)log_ISC,  NULL },
        { "AcceptSecurityContext",         (void *)log_ASC,  NULL },
        { "QueryContextAttributesW",       (void *)log_QCA,  NULL },
        { "QueryContextAttributesExW",     (void *)log_QCP,  NULL },
        { "DeleteSecurityContext",         (void *)log_DSC,  NULL },
        { "FreeCredentialsHandle",         (void *)log_FCH,  NULL },
        { "EnumerateSecurityPackagesW",    (void *)log_ENUM, NULL },
        { "QuerySecurityPackageInfoW",     (void *)log_QSPI, NULL },
        { "FreeContextBuffer",             (void *)log_FCB,  NULL },
        { "CompleteAuthToken", (void *)wrap_T0, NULL },
        { "ApplyControlToken", (void *)wrap_T1, NULL },
        { "MakeSignature", (void *)wrap_T2, NULL },
        { "VerifySignature", (void *)wrap_T3, NULL },
        { "EncryptMessage", (void *)wrap_T4, NULL },
        { "DecryptMessage", (void *)wrap_T5, NULL },
        { "QueryCredentialsAttributesW", (void *)wrap_T6, NULL },
        { "QueryCredentialsAttributesA", (void *)wrap_T7, NULL },
        { "SetContextAttributesW", (void *)wrap_T8, NULL },
        { "ImpersonateSecurityContext", (void *)wrap_T9, NULL },
        { "RevertSecurityContext", (void *)wrap_T10, NULL },
        { "QuerySecurityContextToken", (void *)wrap_T11, NULL },
        { "ExportSecurityContext", (void *)wrap_T12, NULL },
        { "ImportSecurityContextW", (void *)wrap_T13, NULL },
    };
    const int n_want = (int)( sizeof(want) / sizeof(want[0]) );
    PSecurityFunctionTableW copy;
    HMODULE sec = GetModuleHandleW( L"secur32.dll" );
    int i, w;

    copy = malloc( sizeof(*copy) + 512 );
    if (!copy) return 0;
    memcpy( copy, real, sizeof(*copy) );

    for (w = 0; w < n_want; w++) {
        want[w].real = (void *)GetProcAddress( sec, want[w].name );
        if (!want[w].real) continue;
        if (!strcmp( want[w].name, "InitializeSecurityContextW" )) orig_ISC = want[w].real;
        else if (!strcmp( want[w].name, "AcceptSecurityContext" ))  orig_ASC = want[w].real;
        else if (!strcmp( want[w].name, "QueryContextAttributesW" )) orig_QCA = want[w].real;
        else if (!strcmp( want[w].name, "QueryContextAttributesExW" )) orig_QCP = want[w].real;
        else if (!strcmp( want[w].name, "DeleteSecurityContext" ))  orig_DSC = want[w].real;
        else if (!strcmp( want[w].name, "FreeCredentialsHandle" ))  orig_FCH = want[w].real;
        else if (!strcmp( want[w].name, "EnumerateSecurityPackagesW" )) orig_ENUM = want[w].real;
        else if (!strcmp( want[w].name, "QuerySecurityPackageInfoW" ))  orig_QSPI = want[w].real;
        else if (!strcmp( want[w].name, "FreeContextBuffer" ))      orig_FCB = want[w].real;
        else if (!strcmp( want[w].name, "CompleteAuthToken" )) orig_T0 = want[w].real;
        else if (!strcmp( want[w].name, "ApplyControlToken" )) orig_T1 = want[w].real;
        else if (!strcmp( want[w].name, "MakeSignature" )) orig_T2 = want[w].real;
        else if (!strcmp( want[w].name, "VerifySignature" )) orig_T3 = want[w].real;
        else if (!strcmp( want[w].name, "EncryptMessage" )) orig_T4 = want[w].real;
        else if (!strcmp( want[w].name, "DecryptMessage" )) orig_T5 = want[w].real;
        else if (!strcmp( want[w].name, "QueryCredentialsAttributesW" )) orig_T6 = want[w].real;
        else if (!strcmp( want[w].name, "QueryCredentialsAttributesA" )) orig_T7 = want[w].real;
        else if (!strcmp( want[w].name, "SetContextAttributesW" )) orig_T8 = want[w].real;
        else if (!strcmp( want[w].name, "ImpersonateSecurityContext" )) orig_T9 = want[w].real;
        else if (!strcmp( want[w].name, "RevertSecurityContext" )) orig_T10 = want[w].real;
        else if (!strcmp( want[w].name, "QuerySecurityContextToken" )) orig_T11 = want[w].real;
        else if (!strcmp( want[w].name, "ExportSecurityContext" )) orig_T12 = want[w].real;
        else if (!strcmp( want[w].name, "ImportSecurityContextW" )) orig_T13 = want[w].real;
    }
    orig_ACH = (void *)GetProcAddress( sec, "AcquireCredentialsHandleW" );

    for (w = 0; w < n_want; w++) {
        void **word = (void **)copy;
        int n = (int)( sizeof(*copy) / sizeof(void *) ), hits = 0;
        if (!want[w].real) { printf( "  [sspi]   (secur32 exports no %s)\n", want[w].name ); continue; }
        for (i = 0; i < n; i++)
            if (word[i] == want[w].real) { word[i] = want[w].wrap; hits++; }
        printf( "  [sspi]   %s @ %p -> %d table slot(s)\n", want[w].name, want[w].real, hits );
        if (hits) g_wrap[g_wrap_n].name = want[w].name, g_wrap[g_wrap_n].real = want[w].real,
                  g_wrap[g_wrap_n].wrap = want[w].wrap, g_wrap_n++;
    }
    printf( "  [sspi] real table=%p copy=%p entries_replaced=%d\n", (void *)real, (void *)copy, g_wrap_n );
    fflush( stdout );
    g_sspi_copy = copy;
    return 1;
}

static void install_sspi_hook( void )
{
    const WCHAR *mods[3] = { NULL, L"Security.dll", L"secur32.dll" };
    HMODULE sec;
    void *real_fn = NULL;
    PSecurityFunctionTableW real;
    int m;

    sec = LoadLibraryW( L"secur32.dll" );
    if (!sec) { printf( "  [sspi] secur32.dll not loadable\n" ); return; }

    real_fn = (void *)GetProcAddress( sec, "InitSecurityInterfaceW" );
    if (!real_fn) { printf( "  [sspi] secur32 exports no InitSecurityInterfaceW\n" ); return; }
    real = ((PSecurityFunctionTableW (SEC_ENTRY *)(void))real_fn)();
    printf( "  [sspi] secur32!InitSecurityInterfaceW @ %p -> real table %p\n", real_fn, (void *)real );
    if (!real) return;
    if (!build_table_copy( real )) return;

    for (m = 1; m < 3; m++) {
        HMODULE h = GetModuleHandleW( mods[m] );
        void *fn;
        if (!h) continue;
        fn = (void *)GetProcAddress( h, "InitSecurityInterfaceW" );
        if (!fn) continue;
        detour_function( fn, (void *)my_ISI );
        printf( "  [sspi] %ls!InitSecurityInterfaceW @ %p detoured -> %p\n", mods[m], fn, (void *)my_ISI );
        g_sspi_detoured++;
    }
    printf( "  [sspi] InitSecurityInterfaceW detoured in %d module(s)\n", g_sspi_detoured );
    fflush( stdout );
}

static void install_gpa_log( HMODULE mod )
{
    patch_iat( mod, "KERNEL32.dll", "GetProcAddress", (void *)hook_GPA, (void **)&orig_GPA );
    printf( "  [gpa] GetProcAddress logging hook installed in msolap.dll (perturbs: see notes)\n" );
    fflush( stdout );
}

/* msolap reaches the SSPI table through LoadLibrary + GetProcAddress, not through its import table.  Every name it
 * resolves dynamically is logged: the provider fetches a lot of its imports this way, so this is where the API
 * surface it actually uses becomes visible. */
static FARPROC WINAPI hook_GPA( HMODULE mod, LPCSTR name )
{
    /* The provider also calls GetProcAddress with an *ordinal* (a small integer that is not a pointer), e.g.
     * `GetProcAddress(ws2_32, 0x6f)`.  Treating that as a string crashes inside msvcrt -- which is what killed the
     * earlier probe versions at exactly this point -- so only dereference a plausible, readable pointer. */
    int named = name && (ULONG_PTR)name > 0x10000 && !IsBadStringPtrA( name, 64 );
    char mname[MAX_PATH] = "?";
    FARPROC r;
    if (mod) K32GetModuleBaseNameA( GetCurrentProcess(), mod, mname, sizeof(mname) );
    r = orig_GPA( mod, name );
    if (named) printf( "  [gpa] %s!%s -> %p\n", mname, name, (void *)r );
    else       printf( "  [gpa] %s!#%lu -> %p\n", mname, (unsigned long)(ULONG_PTR)name, (void *)r );
    fflush( stdout );
    return r;
}

/* Resolve an address to module+offset so a crash says which DLL and where. */
static void print_addr(const char *label, void *addr)
{
    HMODULE mods[512];
    DWORD needed = 0, i;
    printf("  %-14s %p", label, addr);
    if (K32EnumProcessModules(GetCurrentProcess(), mods, sizeof(mods), &needed)) {
        for (i = 0; i < needed / sizeof(HMODULE); i++) {
            MODULEINFO mi;
            char name[MAX_PATH];
            if (!K32GetModuleInformation(GetCurrentProcess(), mods[i], &mi, sizeof(mi))) continue;
            if ((char *)addr >= (char *)mi.lpBaseOfDll &&
                (char *)addr < (char *)mi.lpBaseOfDll + mi.SizeOfImage) {
                if (K32GetModuleBaseNameA(GetCurrentProcess(), mods[i], name, sizeof(name)))
                    printf("  <- %s+0x%lx", name, (unsigned long)((char *)addr - (char *)mi.lpBaseOfDll));
                break;
            }
        }
    }
    printf("\n");
}

static void show_backtrace(const char *why)
{
    void *frames[24];
    USHORT n, i;
    printf("  [hook] %s\n", why);
    n = RtlCaptureStackBackTrace(1, 24, frames, NULL);
    for (i = 0; i < n; i++) {
        char lbl[16];
        snprintf(lbl, sizeof(lbl), "    #%d", i);
        print_addr(lbl, frames[i]);
    }
    fflush(stdout);
}

/* Keep a crash short and informative instead of handing the process to winedbg (which waits on stdin). */
static LONG WINAPI crash_filter(EXCEPTION_POINTERS *ep)
{
    void *frames[24];
    USHORT n, i;
    printf("  [probe] UNHANDLED EXCEPTION code=0x%08lX\n", (unsigned long)ep->ExceptionRecord->ExceptionCode);
    print_addr("fault address", (void *)ep->ExceptionRecord->ExceptionAddress);
    printf("  rip=%p rsp=%p rcx=%p rdx=%p r8=%p r9=%p\n",
           (void *)ep->ContextRecord->Rip, (void *)ep->ContextRecord->Rsp,
           (void *)ep->ContextRecord->Rcx, (void *)ep->ContextRecord->Rdx,
           (void *)ep->ContextRecord->R8, (void *)ep->ContextRecord->R9);
    n = RtlCaptureStackBackTrace(0, 24, frames, NULL);
    for (i = 0; i < n; i++) {
        char lbl[16];
        snprintf(lbl, sizeof(lbl), "frame %2d", i);
        print_addr(lbl, frames[i]);
    }
    fflush(stdout);
    return EXCEPTION_EXECUTE_HANDLER;
}

int main(int argc, char **argv)
{
    const char *dll_path, *conn_str, *query = NULL;
    int do_connect = 1, i, use_tracer = 0, use_hook = 0, use_sspi = 0, max_rows = 0, use_children = 0;
    HRESULT hr;
    HMODULE mod;
    FARPROC proc;
    IClassFactory *cf = NULL;
    IDBInitialize *dbinit = NULL;
    IDBProperties *props = NULL;
    DBPROP prop;
    DBPROPSET propset;

    setvbuf(stdout, NULL, _IONBF, 0);
    SetUnhandledExceptionFilter(crash_filter);
    if (argc < 3) {
        printf("usage: msolapprobe.exe <msolap.dll path|-> <connection string> [--noconnect] [--query <text>|--query-file <path>] [--rows N] [--children]\n");
        printf("                     [--columns] [--native] [--fetch N] [--parent] [--status] [--exec-iid rows|multi]\n");
        return 2;
    }
    dll_path = argv[1];
    conn_str = argv[2];
    for (i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "--noconnect"))
            do_connect = 0;
        else if (!strcmp(argv[i], "--query") && i + 1 < argc)
            query = argv[++i];
        else if (!strcmp(argv[i], "--query-file") && i + 1 < argc)
            query = read_text_file( argv[++i] );   /* no shell quoting: Power BI's DAX is full of quotes */
        else if (!strcmp(argv[i], "--tracer"))
            use_tracer = 1;
        else if (!strcmp(argv[i], "--hook"))
            use_hook = 1;
        else if (!strcmp(argv[i], "--rows") && i + 1 < argc)
            max_rows = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--children"))
            use_children = 1;
        else if (!strcmp(argv[i], "--columns"))
            g_columns = 1;
        else if (!strcmp(argv[i], "--native"))
            g_native = 1;
        else if (!strcmp(argv[i], "--status"))
            g_status = 1;
        else if (!strcmp(argv[i], "--parent"))
            g_parent = 1;
        else if (!strcmp(argv[i], "--fetch") && i + 1 < argc)
            g_fetch = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--exec-iid") && i + 1 < argc)
            g_exec_iid = !strcmp(argv[++i], "multi") ? 2 : 1;
        else if (!strcmp(argv[i], "--app-props"))
            g_app_props = 1;
        else if (!strcmp(argv[i], "--skip-col") && i + 1 < argc)
            g_skip_col = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--only-col") && i + 1 < argc)
            g_only_col = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--big-buffers"))
            g_big_buffers = 1;
        else if (!strcmp(argv[i], "--force-type") && i + 1 < argc)
            g_force_type = (int)strtol(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--sspi"))
            use_hook = 1, use_sspi = 1;
        else if (!strcmp(argv[i], "--gpa"))
            g_gpa_log = 1;
        else if (!strcmp(argv[i], "--spnego"))
            use_hook = 1, use_sspi = 1, g_spnego = 1;
        else if (!strcmp(argv[i], "--sink"))
            g_sink_fix = 1;
        else if (!strcmp(argv[i], "--tracer-late"))
            use_tracer = 1, g_tracer_late = 1;
        else if (!strcmp(argv[i], "--freeok"))
            use_hook = 1, use_sspi = 1, g_free_ok = 1;
        else if (!strncmp(argv[i], "--pkgname=", 10)) {
            use_hook = 1, use_sspi = 1, g_pkg_name = 1;
            MultiByteToWideChar( CP_ACP, 0, argv[i] + 10, -1, g_pkg_name_w, 64 );
        }
    }

    printf("MSOLAP probe\n");
    printf("  dll          %s\n", dll_path);
    printf("  conn string  %s\n", conn_str);
    printf("  connect      %s\n", do_connect ? "yes" : "no");
    printf("  query        %s\n", query ? query : "(none)");

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    step("CoInitializeEx(APARTMENTTHREADED)", hr);
    if (hr == RPC_E_CHANGED_MODE) hr = S_OK;

    /* 1. the provider DLL, exactly as MsolapClassFactory loads it */
    if (!strcmp(dll_path, "-"))
        mod = LoadLibraryW(L"msolap");
    else {
        WCHAR wide[MAX_PATH];
        MultiByteToWideChar(CP_ACP, 0, dll_path, -1, wide, MAX_PATH);
        SetLastError(0);
        mod = LoadLibraryExW(wide, NULL,
                             LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    }
    step("LoadLibraryExW(msolap.dll, 0x1100)", mod ? S_OK : HRESULT_FROM_WIN32(GetLastError()));
    if (!mod) { dump_error_info(); return 1; }

    if (use_hook)
        install_iat_hooks(mod);
    if (use_sspi)
        install_sspi_hook();
    if (g_gpa_log)
        install_gpa_log(mod);

    proc = GetProcAddress(mod, "DllGetClassObject");
    step("GetProcAddress(DllGetClassObject)", proc ? S_OK : HRESULT_FROM_WIN32(GetLastError()));
    if (!proc) return 1;

    /* 2. class factory out of the DLL, then IDBInitialize — no registry, no CoCreateInstance */
    hr = ((HRESULT (WINAPI *)(REFCLSID, REFIID, void **))proc)(
            &CLSID_MSOLAP_PROBE, &IID_IClassFactory, (void **)&cf);
    step("DllGetClassObject(CLSID_MSOLAP,IClassFactory)", hr);
    if (FAILED(hr)) goto done;

    hr = IClassFactory_CreateInstance(cf, NULL, &IID_IDBInitialize, (void **)&dbinit);
    step("IClassFactory::CreateInstance(IDBInitialize)", hr);
    if (FAILED(hr)) goto done;

    /* 3. the provider trace callback, exactly where MsolapWrapper installs its NativeProxyTracer
     * (--tracer-late defers it to the first SSPI call: see g_tracer_late) */
    if (use_tracer && !g_tracer_late)
        install_tracer(dbinit);
    else if (g_tracer_late)
        g_dbinit_late = dbinit;

    /* 4. what Power BI sets: DBPROP_INIT_PROVIDERSTRING in DBPROPSET_DBINIT */
    memset(&prop, 0, sizeof(prop));
    memset(&propset, 0, sizeof(propset));
    propset.guidPropertySet = DBPROPSET_DBINIT;
    propset.cProperties = 1;
    propset.rgProperties = &prop;
    {
        WCHAR wide[4096];
        MultiByteToWideChar(CP_ACP, 0, conn_str, -1, wide, 4096);
        prop.dwPropertyID = DBPROP_INIT_PROVIDERSTRING;
        prop.dwOptions = DBPROPOPTIONS_REQUIRED;
        prop.dwStatus = 0;
        VariantInit(&prop.vValue);
        prop.vValue.vt = VT_BSTR;
        prop.vValue.bstrVal = SysAllocString(wide);
    }

    hr = IDBInitialize_QueryInterface(dbinit, &IID_IDBProperties, (void **)&props);
    step("IDBInitialize::QueryInterface(IDBProperties)", hr);
    if (FAILED(hr)) goto done;

    hr = IDBProperties_SetProperties(props, 1, &propset);
    step("IDBProperties::SetProperties(DBPROPSET_DBINIT)", hr);
    if (FAILED(hr)) { dump_error_info(); goto done; }

    if (!do_connect) {
        printf("  (--noconnect: stopping before Initialize)\n");
        goto done;
    }

    /* 4. IDBInitialize::Initialize — the step that fails in the app */
    SetLastError(0);
    hr = IDBInitialize_Initialize(dbinit);
    step("IDBInitialize::Initialize()", hr);
    if (FAILED(hr)) { dump_error_info(); goto done; }

    if (query) {
        IDBCreateSession *cs = NULL;
        IOpenRowset *ors = NULL;
        IDBCreateCommand *cc = NULL;
        ICommandText *cmd = NULL;
        IRowset *rs = NULL;
        DBROWCOUNT nrows = 0;
        WCHAR wide[4096];

        MultiByteToWideChar(CP_ACP, 0, query, -1, wide, 4096);
        hr = IDBInitialize_QueryInterface(dbinit, &IID_IDBCreateSession, (void **)&cs);
        step("QueryInterface(IDBCreateSession)", hr);
        if (SUCCEEDED(hr)) {
            hr = IDBCreateSession_CreateSession(cs, NULL, &IID_IDBCreateCommand, (IUnknown **)&cc);
            step("IDBCreateSession::CreateSession", hr);
        }
        if (SUCCEEDED(hr)) {
            hr = IDBCreateCommand_CreateCommand(cc, NULL, &IID_ICommandText, (IUnknown **)&cmd);
            step("IDBCreateCommand::CreateCommand", hr);
        }
        if (SUCCEEDED(hr)) {
            hr = ICommandText_SetCommandText(cmd, &DBGUID_DEFAULT, wide);
            step("ICommandText::SetCommandText", hr);
        }
        if (SUCCEEDED(hr)) {
            const IID *exec_iid = (g_exec_iid == 2) ? &IID_IMultipleResults
                                : (g_exec_iid == 1) ? &IID_IRowset
                                : (use_children ? &IID_IMultipleResults : &IID_IRowset);
            int is_multi = (exec_iid == &IID_IMultipleResults);
            if (g_app_props)
                apply_app_props( (IUnknown *)cmd );   /* MsolapWrapper does this between Create and Execute */
            hr = ICommandText_Execute(cmd, NULL, exec_iid, NULL, NULL, (IUnknown **)&rs);
            step(is_multi ? "ICommandText::Execute(IID_IMultipleResults)"
                          : "ICommandText::Execute(IID_IRowset)", hr);
            if (SUCCEEDED(hr)) {
                step("query executed", S_OK);
                printf("  binding      %s, cRows per GetNextRows=%d\n",
                       g_native ? "each column's own type (ATL CDynamicAccessor style)" : "DBTYPE_WSTR",
                       g_fetch);
                if (use_children || is_multi) {
                    walk_result( (IUnknown *)rs, max_rows );
                } else {
                    if (max_rows > 0) dump_rowset( rs, max_rows );
                    if (g_parent) walk_parent( rs, max_rows );
                }
            }
        }
        if (rs) IRowset_Release(rs);
        if (cmd) ICommandText_Release(cmd);
        if (cc) IDBCreateCommand_Release(cc);
        if (ors) IOpenRowset_Release(ors);
        if (cs) IDBCreateSession_Release(cs);
    }

done:
    if (props) IDBProperties_Release(props);
    if (dbinit) IDBInitialize_Release(dbinit);
    if (cf) IClassFactory_Release(cf);
    CoUninitialize();
    printf("MSOLAP probe: %s (final hr=0x%08lX)\n", SUCCEEDED(hr) ? "SUCCESS" : "FAILURE", (unsigned long)hr);
    return SUCCEEDED(hr) ? 0 : 1;
}
