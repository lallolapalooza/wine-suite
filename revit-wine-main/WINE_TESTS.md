# Wine-suite regression tests for the patch series

One regression test per patch that changes Wine code, in that module's `dlls/<module>/tests/` suite and wired
into `START_TEST`. The patch files are **not** modified: the tests are in
`patches/0103-tests-cover-the-series.patch`, and
`tools/run_wine_tests.sh` builds and runs a module's suite against this fork:

    tools/run_wine_tests.sh --list              # per patch: the modules it touches, and whether it carries a test
    tools/run_wine_tests.sh kernel32 thread     # dlls/kernel32/tests/thread.c, log in logs/tests/

## How each verdict was measured

* **with the patch**: a build of this tree, the test run from it.
* **without the patch**: a build of a pristine Wine 11.18 (the release tarball), with the test files copied in
  and the test binaries linked against the *pristine* specs - a revert inside a warm patched tree does not work
  for the export patches, because Wine resolves the missing export to its stub entry and the call aborts the run
  instead of producing a verdict.

Columns are `failures with the patch` / `failures without it`; the pre-existing failures of a suite in this
environment are named, so the delta that belongs to the test is visible.

| patch | test | with | without |
|---|---|---|---|
| 0001 | wintrust `softpub` | 0 | 3 (`WTD_CHOICE_BLOB is not supported, got 0x57`) |
| 0002 | advapi32 `registry` | 19 (all pre-existing `test_redirection`, this x86_64-only prefix has no WOW64 redirection) | 22 (the extra three are the new test: `RegOpenKeyExA failed`) |
| 0003 | urlmon `sec_mgr` | 0 | 1 (`zone=-1, expected URLZONE_INTERNET`) |
| 0006 | ws2_32 `protocol` (hosts file) | 0 | **2** (shared with 0012: `getaddrinfo(…hosts-test.invalid) failed with error 11001`) |
| 0007 | crypt32 `store` | 0 | 5 (`CertOpenStore failed: 00000002`) |
| 0008 | kernel32 `file` | 0 | 2 (`CreateIoCompletionPort on a non-overlapped handle failed, error 87`) |
| 0009 | ntdll `pipe` | 0 | 7 (`NtSetInformationFile(…) on a Unix pipe returned 0xc0000024`, `PeekNamedPipe … error 50`) |
| 0010 | kernel32 `thread` | 0 | 1 (`FlsGetValue2 is not exported`) |
| 0010 | kernel32 `process` | 1 (pre-existing `Console:winBottom expected 24, but got 22`) | 4 (`GetProcessUserModeExceptionPolicy is not exported`) |
| 0010 | ntdll `path` | 0 | 1 (`RtlAreLongPathsEnabled is not exported`) |
| 0010 | dnsapi `query` | 0 | 1 (`DnsIsZtEnabled is not exported`) |
| 0012 | ws2_32 `protocol` (NS_NLA) | 0 | **2** (shared with 0006: `WSALookupServiceBeginW(NS_NLA) failed with error 8`) |
| 0014 | secur32 `secur32` | 0 | 10 (`8: got 1332`, ERROR_NONE_MAPPED) |
| 0102 | dxgi `dxgi` | 394 (pre-existing suite failures) | **395** (the extra one is `dxgi.c:2478 Got unexpected hr 0x80004001` - the stubbed CreateSwapChainForComposition) |

0016 already carried its test with the patch (`dlls/kernel32/tests/actctx.c`), and so do 0100 (ncrypt) and 0101
(dcomp) where present, so nothing was added for them.

## Not covered, and why

* **0004 (server session 0)**, **0013 (winex11 stale-window errors)** and **0015 (msiexec command line)** have no
  behaviour a Wine module suite can reach from inside a process: a wineserver-managed session, an X11 error path,
  and a program's command-line parser with no test module of its own.
* The two patches whose only effect is that a stub is no longer reached are covered by the assertions listed
  above; none of the tests is a `win_skip`-only placeholder.
