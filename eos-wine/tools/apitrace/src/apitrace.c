/*
 * apitrace.exe -- launcher/injector for apihook.dll.
 *
 *   apitrace.exe [--cfg F] [--out L] [--poll MS] [--dll F] [--timeout S]
 *                [--nowait] [--pid N] -- <target.exe> [args...]
 *
 * Starts the target suspended (CreateProcessW + CREATE_SUSPENDED), injects
 * apihook.dll with a remote LoadLibraryW, waits for the trace-ready event,
 * then resumes the target.  --pid attaches to an already running process.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -o apitrace.exe apitrace.c -lshell32
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static void die(const char* what)
{
	fprintf(stderr, "apitrace: %s failed, GetLastError=%lu\n", what, (unsigned long)GetLastError());
	exit(2);
}

/* --- absolute path helper -------------------------------------------------- */
static wchar_t* abspath(const wchar_t* p, wchar_t* out, DWORD n)
{
	DWORD r = GetFullPathNameW(p, n, out, NULL);
	if (!r || r >= n) { wcsncpy(out, p, n - 1); out[n - 1] = 0; }
	return out;
}

/* --- quote argv for CreateProcessW ---------------------------------------- */
static void append_quoted(wchar_t* dst, size_t cap, const wchar_t* s)
{
	size_t len = wcslen(dst);
	int need = (s[0] == 0 || wcspbrk(s, L" \t\"") != NULL);
	if (need) dst[len++] = L'"';
	for (; *s; s++) {
		if (*s == L'"') {
			dst[len++] = L'\\';
			dst[len++] = L'"';
		} else if (*s == L'\\') {
			const wchar_t* q = s;
			int nbs = 0;
			while (*q == L'\\') { nbs++; q++; }
			if (*q == L'"' || *q == 0) nbs *= 2;
			while (nbs--) dst[len++] = L'\\';
			if (*q == 0) break;
			if (*q == L'"') { dst[len++] = L'\\'; dst[len++] = L'"'; s = q; continue; }
			s = q - 1;
		} else {
			dst[len++] = *s;
		}
	}
	if (need) dst[len++] = L'"';
	dst[len] = 0;
	(void)cap;
}

/* --- remote injection ------------------------------------------------------ */
static DWORD inject_dll(HANDLE hp, const wchar_t* dll)
{
	SIZE_T bytes = (wcslen(dll) + 1) * sizeof(wchar_t);
	void* remote;
	HMODULE k32;
	FARPROC loadlib;
	HANDLE ht;
	DWORD rc = 0;
	BOOL ok;

	remote = VirtualAllocEx(hp, NULL, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (!remote) die("VirtualAllocEx");
	if (!WriteProcessMemory(hp, remote, dll, bytes, NULL)) die("WriteProcessMemory");
	k32 = GetModuleHandleW(L"kernel32.dll");
	loadlib = GetProcAddress(k32, "LoadLibraryW");
	if (!loadlib) die("GetProcAddress(LoadLibraryW)");
	ht = CreateRemoteThread(hp, NULL, 0, (LPTHREAD_START_ROUTINE)(void*)loadlib,
				remote, 0, NULL);
	if (!ht) die("CreateRemoteThread");
	if (WaitForSingleObject(ht, 30000) != WAIT_OBJECT_0) {
		fprintf(stderr, "apitrace: inject timed out\n");
		exit(3);
	}
	ok = GetExitCodeThread(ht, &rc);
	CloseHandle(ht);
	VirtualFreeEx(hp, remote, 0, MEM_RELEASE);
	if (!ok) die("GetExitCodeThread");
	if (rc == 0) {
		fprintf(stderr, "apitrace: target LoadLibraryW failed (dll=%S)\n", dll);
		exit(4);
	}
	return rc;
}

int main(void)
{
	int argc = 0;
	wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	int attach = 0;
	wchar_t cfgw[MAX_PATH] = L"", outw[MAX_PATH] = L"", dllw[MAX_PATH] = L"";
	wchar_t readyw[128] = L"";
	wchar_t exedir[MAX_PATH], tmp[MAX_PATH];
	wchar_t cmdline[32768] = L"";
	wchar_t* target = NULL;
	DWORD pid = 0, timeout_s = 0, poll = 200, base = 0;
	int nowait = 0, i, sep = -1;
	HANDLE hp = NULL, ready = NULL;
	char cfga[MAX_PATH] = "", outa[MAX_PATH] = "", readya[128] = "";
	char jobpath[MAX_PATH];
	FILE* f;
	PROCESS_INFORMATION pi;
	STARTUPINFOW siDummy;

	if (argc < 2) {
		fprintf(stderr,
			"usage: apitrace.exe [--cfg F] [--out L] [--poll MS] [--dll F]\n"
			"                   [--timeout S] [--nowait] [--pid N] -- <target.exe> [args...]\n");
		return 1;
	}
	for (i = 1; i < argc; i++) {
		if (!wcscmp(argv[i], L"--")) { sep = i; break; }
		if (!wcscmp(argv[i], L"--cfg") && i + 1 < argc) { wcsncpy(cfgw, argv[++i], MAX_PATH - 1); }
		else if (!wcscmp(argv[i], L"--out") && i + 1 < argc) { wcsncpy(outw, argv[++i], MAX_PATH - 1); }
		else if (!wcscmp(argv[i], L"--dll") && i + 1 < argc) { wcsncpy(dllw, argv[++i], MAX_PATH - 1); }
		else if (!wcscmp(argv[i], L"--pid") && i + 1 < argc) { pid = (DWORD)_wtoi(argv[++i]); attach = 1; }
		else if (!wcscmp(argv[i], L"--timeout") && i + 1 < argc) { timeout_s = (DWORD)_wtoi(argv[++i]); }
		else if (!wcscmp(argv[i], L"--poll") && i + 1 < argc) { poll = (DWORD)_wtoi(argv[++i]); }
		else if (!wcscmp(argv[i], L"--nowait")) nowait = 1;
		else { fprintf(stderr, "apitrace: unknown option %ls\n", argv[i]); return 1; }
	}
	if (sep >= 0 && sep + 1 < argc) target = argv[sep + 1];

	GetModuleFileNameW(NULL, tmp, MAX_PATH);
	wcsncpy(exedir, tmp, MAX_PATH - 1);
	{
		wchar_t* p = wcsrchr(exedir, L'\\');
		if (p) p[1] = 0; else exedir[0] = 0;
	}
	if (!dllw[0]) _snwprintf(dllw, MAX_PATH - 1, L"%sapihook.dll", exedir);
	if (!cfgw[0]) _snwprintf(cfgw, MAX_PATH - 1, L"%sapitrace.cfg", exedir);
	if (!outw[0]) _snwprintf(outw, MAX_PATH - 1, L"%sapitrace.log", exedir);
	{
		/* GetFullPathNameW is not documented to support aliased in/out buffers */
		wchar_t t1[MAX_PATH], t2[MAX_PATH], t3[MAX_PATH];
		abspath(cfgw, t1, MAX_PATH); wcsncpy(cfgw, t1, MAX_PATH - 1); cfgw[MAX_PATH - 1] = 0;
		abspath(outw, t2, MAX_PATH); wcsncpy(outw, t2, MAX_PATH - 1); outw[MAX_PATH - 1] = 0;
		abspath(dllw, t3, MAX_PATH); wcsncpy(dllw, t3, MAX_PATH - 1); dllw[MAX_PATH - 1] = 0;
	}
	if (GetFileAttributesW(dllw) == INVALID_FILE_ATTRIBUTES) {
		fprintf(stderr, "apitrace: cannot find %ls\n", dllw);
		return 2;
	}
	WideCharToMultiByte(CP_ACP, 0, cfgw, -1, cfga, MAX_PATH, NULL, NULL);
	WideCharToMultiByte(CP_ACP, 0, outw, -1, outa, MAX_PATH, NULL, NULL);

	/* --- start or attach -------------------------------------------------- */
	if (pid) {
		hp = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
				 PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
				 FALSE, pid);
		if (!hp) die("OpenProcess");
		printf("apitrace: attaching to pid %lu\n", (unsigned long)pid);
	} else {
		wchar_t full[MAX_PATH];
		if (!target) { fprintf(stderr, "apitrace: no target given\n"); return 1; }
		abspath(target, full, MAX_PATH);
		append_quoted(cmdline, 32768, full);
		for (i = sep + 2; i < argc; i++) {
			size_t l = wcslen(cmdline);
			cmdline[l] = L' ';
			cmdline[l + 1] = 0;
			append_quoted(cmdline, 32768, argv[i]);
		}
		memset(&pi, 0, sizeof(pi));
		memset(&siDummy, 0, sizeof(siDummy));
		siDummy.cb = sizeof(siDummy);
		if (!CreateProcessW(NULL, cmdline, NULL, NULL, FALSE, CREATE_SUSPENDED,
				    NULL, NULL, &siDummy, &pi))
			die("CreateProcessW");
		pid = pi.dwProcessId;
		hp = pi.hProcess;
		printf("apitrace: started pid %lu (suspended): %ls\n", (unsigned long)pid, cmdline);
	}

	/* --- announce the job to apihook.dll ---------------------------------- */
	_snwprintf(readyw, 127, L"Local\\apitrace_ready_%lu", (unsigned long)pid);
	WideCharToMultiByte(CP_ACP, 0, readyw, -1, readya, sizeof(readya), NULL, NULL);
	ready = CreateEventW(NULL, TRUE, FALSE, readyw);
	if (!ready) die("CreateEventW");
	{
		char edir[MAX_PATH];
		WideCharToMultiByte(CP_ACP, 0, exedir, -1, edir, MAX_PATH, NULL, NULL);
		_snprintf(jobpath, MAX_PATH - 1, "%sapitrace_%lu.job", edir, (unsigned long)pid);
	}
	f = fopen(jobpath, "wb");
	if (!f) die("fopen(job)");
	fprintf(f, "cfg=%s\nout=%s\nready=%s\npoll=%lu\n", cfga, outa, readya, (unsigned long)poll);
	fclose(f);
	printf("apitrace: dll=%ls\napitrace: cfg=%s\napitrace: out=%s\n", dllw, cfga, outa);

	/* --- inject and wait for the hooks to be live ------------------------- */
	base = inject_dll(hp, dllw);
	printf("apitrace: apihook.dll@0x%lx loaded in pid %lu\n", (unsigned long)base, (unsigned long)pid);
	if (WaitForSingleObject(ready, 60000) == WAIT_OBJECT_0) {
		printf("apitrace: hooks installed (ready event signalled)\n");
	} else {
		fprintf(stderr, "apitrace: warning: ready event not signalled\n");
	}
	CloseHandle(ready);

	if (attach) {                    /* attach mode: nothing more to do */
		if (hp) CloseHandle(hp);
		return 0;
	}
	if (!ResumeThread(pi.hThread)) die("ResumeThread");
	CloseHandle(pi.hThread);
	if (nowait) { CloseHandle(pi.hProcess); return 0; }
	if (timeout_s) {
		if (WaitForSingleObject(pi.hProcess, timeout_s * 1000) == WAIT_TIMEOUT) {
			printf("apitrace: timeout %lus, terminating pid %lu\n",
			       (unsigned long)timeout_s, (unsigned long)pid);
			TerminateProcess(pi.hProcess, 1);
			WaitForSingleObject(pi.hProcess, 5000);
		}
	} else {
		WaitForSingleObject(pi.hProcess, INFINITE);
	}
	{
		DWORD ec = 0;
		GetExitCodeProcess(pi.hProcess, &ec);
		printf("apitrace: pid %lu exited with %lu\n", (unsigned long)pid, (unsigned long)ec);
	}
	CloseHandle(pi.hProcess);
	return 0;
}
