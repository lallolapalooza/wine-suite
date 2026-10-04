/*
 * asimp - black-box behaviour probe for the one call that stops Power BI's Analysis Services engine
 * (msmdsrv.exe) from starting under Wine: anonymous-token impersonation.
 *
 * The engine's TCP listener does socket/bind/listen (all of which succeed under Wine), then calls
 * NtImpersonateAnonymousToken(GetCurrentThread()) - and Wine's implementation is a stub returning
 * STATUS_NOT_IMPLEMENTED.  msmdsrv turns that into "ListenToPortFail", closes the socket, fails to start
 * the service and exits without ever writing msmdsrv.port.txt, which is what Power BI Desktop reports as
 * AnalysisServicesProcessUnexpectedExitException.
 *
 * This probe measures the *contract* of the call so the fix can be written to match Windows rather than to
 * merely return success: does it succeed, what does the resulting thread token look like (user SID, groups,
 * impersonation level, token type), and what happens on the documented edge cases (a bad handle, calling it
 * twice, reverting afterwards).
 *
 * Everything is resolved with GetProcAddress: the same binary must run on Windows (reference) and under Wine
 * (our implementation), and the interesting datum is which DLL answered with what status.
 *
 * usage: asimp.exe [logfile]
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>

typedef LONG NTSTATUS;
typedef NTSTATUS (NTAPI *pNtImpersonateAnonymousToken)(HANDLE);
typedef BOOL (WINAPI *pImpersonateAnonymousToken)(HANDLE);

#define STATUS_SUCCESS 0x00000000

static FILE *g_log;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    if (g_log) vfprintf(g_log, fmt, ap);
    va_end(ap);
    fflush(stdout);
    if (g_log) fflush(g_log);
}

static void say_sid(const char *label, PSID sid)
{
    LPSTR s = NULL;
    if (sid && ConvertSidToStringSidA(sid, &s))
    {
        say("  %-22s %s\n", label, s);
        LocalFree(s);
    }
    else
        say("  %-22s <no SID: ConvertSidToStringSid err %lu>\n", label, GetLastError());
}

/* everything a caller can learn about the thread's token through OpenThreadToken */
static void dump_thread_token(void)
{
    HANDLE tok = NULL;
    DWORD size = 0, i;
    TOKEN_USER *user;
    TOKEN_GROUPS *groups;
    TOKEN_PRIMARY_GROUP *pg;
    TOKEN_STATISTICS *stats;
    TOKEN_TYPE type;
    SECURITY_IMPERSONATION_LEVEL level;

    if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
    {
        say("  OpenThreadToken(TOKEN_QUERY, openAsSelf=TRUE) failed: err=%lu\n", GetLastError());
        return;
    }

    size = 0;
    if (GetTokenInformation(tok, TokenUser, NULL, 0, &size) || GetLastError() == ERROR_INSUFFICIENT_BUFFER)
    {
        user = malloc(size);
        if (GetTokenInformation(tok, TokenUser, user, size, &size)) say_sid("TokenUser:", user->User.Sid);
        else say("  TokenUser: GetTokenInformation err=%lu\n", GetLastError());
        free(user);
    }

    size = 0;
    if (GetTokenInformation(tok, TokenGroups, NULL, 0, &size) || GetLastError() == ERROR_INSUFFICIENT_BUFFER)
    {
        groups = malloc(size);
        if (GetTokenInformation(tok, TokenGroups, groups, size, &size))
        {
            say("  TokenGroups:            %lu\n", groups->GroupCount);
            for (i = 0; i < groups->GroupCount && i < 20; i++)
            {
                say_sid("    group:", groups->Groups[i].Sid);
                say("      attrs: 0x%08x\n", groups->Groups[i].Attributes);
            }
            if (groups->GroupCount > 20) say("    ... %lu more\n", groups->GroupCount - 20);
        }
        else say("  TokenGroups: GetTokenInformation err=%lu\n", GetLastError());
        free(groups);
    }

    size = 0;
    if (GetTokenInformation(tok, TokenPrimaryGroup, NULL, 0, &size) || GetLastError() == ERROR_INSUFFICIENT_BUFFER)
    {
        pg = malloc(size);
        if (GetTokenInformation(tok, TokenPrimaryGroup, pg, size, &size)) say_sid("TokenPrimaryGroup:", pg->PrimaryGroup);
        free(pg);
    }

    size = sizeof(type);
    if (GetTokenInformation(tok, TokenType, &type, size, &size))
        say("  TokenType:              %s\n", type == TokenPrimary ? "TokenPrimary" : "TokenImpersonation");
    else
        say("  TokenType: err=%lu\n", GetLastError());

    size = sizeof(level);
    if (GetTokenInformation(tok, TokenImpersonationLevel, &level, size, &size))
        say("  TokenImpersonationLevel %d (0=Anonymous 1=Identification 2=Impersonation 3=Delegation)\n", (int)level);
    else
        say("  TokenImpersonationLevel err=%lu\n", GetLastError());

    size = 0;
    if (GetTokenInformation(tok, TokenStatistics, NULL, 0, &size) || GetLastError() == ERROR_INSUFFICIENT_BUFFER)
    {
        stats = malloc(size);
        if (GetTokenInformation(tok, TokenStatistics, stats, size, &size))
            say("  TokenStatistics:        TokenId=%08lx:%08lx AuthenticationId=%08lx:%08lx\n",
                stats->TokenId.HighPart, stats->TokenId.LowPart,
                stats->AuthenticationId.HighPart, stats->AuthenticationId.LowPart);
        free(stats);
    }

    CloseHandle(tok);
}

int main(int argc, char **argv)
{
    HMODULE ntdll, k32;
    pNtImpersonateAnonymousToken nt_imp = NULL;
    pImpersonateAnonymousToken k32_imp = NULL;
    NTSTATUS status;
    HANDLE bad;
    TOKEN_STATISTICS stats_before, stats_after;

    if (argc > 1) g_log = fopen(argv[1], "w");

    say("asimp: anonymous-token impersonation probe\n");

    ntdll = GetModuleHandleA("ntdll.dll");
    k32 = GetModuleHandleA("kernelbase.dll");
    if (!k32) k32 = LoadLibraryA("kernelbase.dll");
    if (!k32) k32 = LoadLibraryA("advapi32.dll");

    if (ntdll) nt_imp = (pNtImpersonateAnonymousToken)(void *)GetProcAddress(ntdll, "NtImpersonateAnonymousToken");
    if (k32) k32_imp = (pImpersonateAnonymousToken)(void *)GetProcAddress(k32, "ImpersonateAnonymousToken");

    say("  ntdll!NtImpersonateAnonymousToken  %s\n", nt_imp ? "resolved" : "NOT FOUND");
    say("  kernelbase!ImpersonateAnonymousToken %s (from %s)\n", k32_imp ? "resolved" : "NOT FOUND",
        k32 ? "kernelbase" : "advapi32");

    /* what the thread token looks like before we touch it */
    say("\n-- before ------------------------------------------------------------\n");
    memset(&stats_before, 0, sizeof(stats_before));
    {
        HANDLE tok = NULL;
        DWORD size = sizeof(stats_before);
        if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
        {
            GetTokenInformation(tok, TokenStatistics, &stats_before, size, &size);
            CloseHandle(tok);
            say("  (thread already has a token)\n");
        }
        else
            say("  OpenThreadToken before impersonation: err=%lu (no thread token - expected)\n", GetLastError());
    }

    /* ---- the NT call the engine makes --------------------------------------------------------- */
    say("\n-- NtImpersonateAnonymousToken(GetCurrentThread()) --------------------\n");
    if (!nt_imp)
    {
        say("  skipped: symbol not found\n");
    }
    else
    {
        status = nt_imp(GetCurrentThread());
        say("  status = 0x%08lx\n", (unsigned long)status);
        if (status == STATUS_SUCCESS)
        {
            dump_thread_token();
            say("  RevertToSelf() -> %d (err=%lu)\n", RevertToSelf(), GetLastError());
        }
    }

    /* ---- the kernelbase/advapi32 wrapper ------------------------------------------------------ */
    say("\n-- ImpersonateAnonymousToken wrapper ---------------------------------\n");
    if (k32_imp)
    {
        SetLastError(0xdeadbeef);
        if (k32_imp(GetCurrentThread()))
        {
            say("  returned TRUE (last error untouched=%lu)\n", GetLastError());
            dump_thread_token();
            say("  RevertToSelf() -> %d\n", RevertToSelf());
        }
        else
            say("  returned FALSE, GetLastError=%lu\n", GetLastError());
    }
    else say("  skipped: symbol not found\n");

    /* ---- edge cases ------------------------------------------------------------------------- */
    say("\n-- edge cases -------------------------------------------------------\n");
    if (nt_imp)
    {
        status = nt_imp(NULL);
        say("  NtImpersonateAnonymousToken(NULL)      -> 0x%08lx\n", (unsigned long)status);

        bad = (HANDLE)(ULONG_PTR)0x1234;
        status = nt_imp(bad);
        say("  NtImpersonateAnonymousToken(0x1234)    -> 0x%08lx\n", (unsigned long)status);

        status = nt_imp(GetCurrentProcess());
        say("  NtImpersonateAnonymousToken(process)   -> 0x%08lx\n", (unsigned long)status);

        status = nt_imp(GetCurrentThread());
        say("  first  call                            -> 0x%08lx\n", (unsigned long)status);
        status = nt_imp(GetCurrentThread());
        say("  second call (already anonymous)        -> 0x%08lx\n", (unsigned long)status);
        RevertToSelf();
    }

    /* ---- after reverting, is the thread back to normal? -------------------------------------- */
    say("\n-- after revert ------------------------------------------------------\n");
    {
        HANDLE tok = NULL;
        memset(&stats_after, 0, sizeof(stats_after));
        if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &tok))
            say("  OpenThreadToken: err=%lu (no thread token again - expected)\n", GetLastError());
        else
        {
            DWORD size = sizeof(stats_after);
            GetTokenInformation(tok, TokenStatistics, &stats_after, size, &size);
            CloseHandle(tok);
            say("  thread still has a token Id=%08lx:%08lx\n", stats_after.TokenId.HighPart, stats_after.TokenId.LowPart);
            if (stats_before.TokenId.LowPart == stats_after.TokenId.LowPart &&
                stats_before.TokenId.HighPart == stats_after.TokenId.HighPart)
                say("  (same as before impersonation)\n");
        }
    }

    say("\nasimp: done\n");
    if (g_log) fclose(g_log);
    return 0;
}
