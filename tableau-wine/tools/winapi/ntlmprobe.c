/*
 * ntlmprobe.c — measure the NTLM/Negotiate handshake sequence with secur32, in one process, so the *same binary*
 * reports the same numbers on Windows and under Wine (the method used for the WinRT contract, FINDINGS M24).
 *
 * It replays exactly what Power BI's MSOLAP provider does around its XMLA <Authenticate> exchange: a client
 * AcquireCredentialsHandle for "Negotiate" and repeated InitializeSecurityContext calls, against a server
 * AcceptSecurityContext in the same process.  The interesting column is the status of the *second* client call
 * (the one that consumes the server's NTLM challenge), because that is what tells a client whether it still has a
 * token to send.
 *
 *   ntlmprobe.exe [package|-] [target] [flags]      ("-" = NULL = the default package selection)
 *     package  default "Negotiate"      (MSOLAP asks for "Negotiate" with the SPN below)
 *     target   default "MSOLAPSvc.3/localhost"
 *     flags    default 0x1081e           (the ISC_REQ_* mask MSOLAP passes)
 *
 * Build: x86_64-w64-mingw32-gcc -O1 -o bin/ntlmprobe.exe ntlmprobe.c -lsecur32 -ladvapi32
 */
#define SECURITY_WIN32
#include <windows.h>
#include <sspi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void hex_head(const char *what, SecBuffer *b)
{
    const unsigned char *p = b->pvBuffer;
    unsigned i;
    printf("  %-22s %5lu bytes", what, (unsigned long)b->cbBuffer);
    if (b->cbBuffer && p) {
        char sig[9];
        for (i = 0; i < 8 && i < b->cbBuffer; i++) sig[i] = (p[i] >= 32 && p[i] < 127) ? p[i] : '.';
        sig[8] = 0;
        printf("  [%s]", sig);
    }
    printf("\n");
}

static const char *why(SECURITY_STATUS s)
{
    switch (s) {
    case SEC_E_OK: return "SEC_E_OK";
    case SEC_I_CONTINUE_NEEDED: return "SEC_I_CONTINUE_NEEDED";
    case SEC_E_INCOMPLETE_MESSAGE: return "SEC_E_INCOMPLETE_MESSAGE";
    case SEC_E_NO_CREDENTIALS: return "SEC_E_NO_CREDENTIALS";
    case SEC_E_UNSUPPORTED_FUNCTION: return "SEC_E_UNSUPPORTED_FUNCTION";
    case SEC_E_INVALID_TOKEN: return "SEC_E_INVALID_TOKEN";
    case SEC_E_INVALID_HANDLE: return "SEC_E_INVALID_HANDLE";
    case SEC_E_INTERNAL_ERROR: return "SEC_E_INTERNAL_ERROR";
    case SEC_E_SECPKG_NOT_FOUND: return "SEC_E_SECPKG_NOT_FOUND";
    case SEC_E_LOGON_DENIED: return "SEC_E_LOGON_DENIED";
    default: return "";
    }
}

static void report(const char *what, SECURITY_STATUS s, SecBuffer *out)
{
    printf("  %-26s status=0x%08lX %s\n", what, (unsigned long)s, why(s));
    if (out) hex_head("", out);
}

int main(int argc, char **argv)
{
    const char *package = argc > 1 ? argv[1] : "Negotiate";
    /* "-" means pszPackage = NULL: the *default* package selection, which is what Power BI's MSOLAP provider asks
     * for (AcquireCredentialsHandleW(NULL, …)).  On Windows that is Negotiate/SPNEGO; keeping this reachable from
     * the same binary is what makes the two platforms comparable for the call the provider actually makes. */
    const WCHAR *package_arg = NULL;
    const char *target = argc > 2 ? argv[2] : "MSOLAPSvc.3/localhost";
    ULONG flags = argc > 3 ? (ULONG)strtoul(argv[3], NULL, 0) : 0x1081e;
    WCHAR wpackage[64], wtarget[256];
    CredHandle ccred, scred;
    CtxtHandle cctx, sctx;
    TimeStamp expiry;
    SECURITY_STATUS cst, sst;
    SecBuffer cbuf, sbuf[2], c_in, s_in[2];
    SecBufferDesc cdesc, sdesc, cin_desc, sin_desc;
    static BYTE c_mem[8192], s_mem[8192], c_in_mem[8192], s_in_mem[8192];
    ULONG cattr = 0, sattr = 0;
    int step = 0, skip_server = 0;
    BOOL have_cctx = FALSE, have_sctx = FALSE;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (strcmp( package, "-" ))
    {
        MultiByteToWideChar(CP_ACP, 0, package, -1, wpackage, 64);
        package_arg = wpackage;
    }
    MultiByteToWideChar(CP_ACP, 0, target, -1, wtarget, 256);

    printf("NTLM/Negotiate handshake probe\n");
    printf("  package %s   target %s   flags 0x%lx\n", package_arg ? package : "(default)", target, (unsigned long)flags);

    sst = AcquireCredentialsHandleW(NULL, (SEC_WCHAR *)package_arg, SECPKG_CRED_INBOUND, NULL, NULL, NULL, NULL, &scred, &expiry);
    report("AcquireCredentialsHandle(server)", sst, NULL);
    cst = AcquireCredentialsHandleW(NULL, (SEC_WCHAR *)package_arg, SECPKG_CRED_OUTBOUND, NULL, NULL, NULL, NULL, &ccred, &expiry);
    report("AcquireCredentialsHandle(client)", cst, NULL);
    if (cst) return 1;
    if (sst) {
        /* Wine's default-package selection has failed for INBOUND credentials on some builds; the client half is
         * still worth measuring (and is the half Power BI's provider uses), so the server steps are skipped. */
        printf("  (server side unavailable with this package; measuring the client context only)\n");
        skip_server = 1;
    }

    /* round 1: client produces its initial token */
    cbuf.BufferType = SECBUFFER_TOKEN;
    cbuf.cbBuffer = sizeof(c_mem);
    cbuf.pvBuffer = c_mem;
    cdesc.ulVersion = SECBUFFER_VERSION;
    cdesc.cBuffers = 1;
    cdesc.pBuffers = &cbuf;

    cst = InitializeSecurityContextW(&ccred, NULL, wtarget, flags, 0, 0, NULL, 0,
                                     &cctx, &cdesc, &cattr, &expiry);
    have_cctx = TRUE;
    report("client ISC #1 (no token)", cst, &cbuf);
    /* Which package did the *default* selection (pszPackage = NULL) actually resolve to?  The provider asks for the
     * default package and then reads exactly this back through SECPKG_ATTR_PACKAGE_INFO, so it is the fact that
     * decides whether the two platforms are comparable at all. */
    if (cst == SEC_I_CONTINUE_NEEDED || cst == SEC_E_OK) {
        SecPkgInfoW *info = NULL;
        if (QueryContextAttributesW(&cctx, SECPKG_ATTR_PACKAGE_INFO, &info) == SEC_E_OK && info) {
            printf("  package resolved by AcquireCredentialsHandle(NULL, %s) = \"%ls\" (caps=0x%lx maxToken=%lu)\n",
                   package_arg ? "…" : "NULL", info->Name ? info->Name : L"(null)",
                   (unsigned long)info->fCapabilities, (unsigned long)info->cbMaxToken);
            FreeContextBuffer(info);
        }
    }
    printf("                            (ISC_REQ flags echo 0x%08lx)\n", (unsigned long)cattr);
    if (cst != SEC_I_CONTINUE_NEEDED && cst != SEC_E_OK) return 1;

    for (step = 1; step <= 4 && !skip_server; step++) {
        /* server consumes the client's token */
        memcpy(s_in_mem, cbuf.pvBuffer, cbuf.cbBuffer);
        s_in[0].BufferType = SECBUFFER_TOKEN;
        s_in[0].cbBuffer = cbuf.cbBuffer;
        s_in[0].pvBuffer = s_in_mem;
        s_in[1].BufferType = SECBUFFER_ALERT;
        s_in[1].cbBuffer = 0;
        s_in[1].pvBuffer = NULL;
        sin_desc.ulVersion = SECBUFFER_VERSION;
        sin_desc.cBuffers = 2;
        sin_desc.pBuffers = s_in;

        sbuf[0].BufferType = SECBUFFER_TOKEN;
        sbuf[0].cbBuffer = sizeof(s_mem);
        sbuf[0].pvBuffer = s_mem;
        sbuf[1].BufferType = SECBUFFER_ALERT;
        sbuf[1].cbBuffer = 0;
        sbuf[1].pvBuffer = NULL;
        sdesc.ulVersion = SECBUFFER_VERSION;
        sdesc.cBuffers = 2;
        sdesc.pBuffers = sbuf;

        sst = AcceptSecurityContext(&scred, have_sctx ? &sctx : NULL, &sin_desc,
                                    ASC_REQ_MUTUAL_AUTH | ASC_REQ_CONNECTION | ASC_REQ_INTEGRITY | ASC_REQ_CONFIDENTIALITY | ASC_REQ_REPLAY_DETECT | ASC_REQ_SEQUENCE_DETECT, 0,
                                    &sctx, &sdesc, &sattr, &expiry);
        have_sctx = TRUE;
        report("server ASC", sst, &sbuf[0]);
        if (cst == SEC_E_OK && sst == SEC_E_OK) break;

        /* client consumes the server's token */
        memcpy(c_in_mem, sbuf[0].pvBuffer, sbuf[0].cbBuffer);
        c_in.BufferType = SECBUFFER_TOKEN;
        c_in.cbBuffer = sbuf[0].cbBuffer;
        c_in.pvBuffer = c_in_mem;
        cin_desc.ulVersion = SECBUFFER_VERSION;
        cin_desc.cBuffers = 1;
        cin_desc.pBuffers = &c_in;

        cbuf.BufferType = SECBUFFER_TOKEN;
        cbuf.cbBuffer = sizeof(c_mem);
        cbuf.pvBuffer = c_mem;
        cdesc.ulVersion = SECBUFFER_VERSION;
        cdesc.cBuffers = 1;
        cdesc.pBuffers = &cbuf;

        cst = InitializeSecurityContextW(&ccred, &cctx, wtarget, flags, 0, 0, &cin_desc, 0,
                                        &cctx, &cdesc, &cattr, &expiry);
        report("client ISC (server token in)", cst, &cbuf);
        if (cst != SEC_I_CONTINUE_NEEDED && cst != SEC_E_OK) break;
    }

    printf("handshake ended: client=0x%08lX server=0x%08lX%s\n", (unsigned long)cst, (unsigned long)sst,
           skip_server ? " (server side skipped: its AcquireCredentialsHandle failed)" : "");
    return (cst == SEC_E_OK && sst == SEC_E_OK) ? 0 : 1;
}
