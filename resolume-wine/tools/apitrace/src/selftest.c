/*
 * selftest.exe -- calls a handful of kernel32 APIs with known arguments and
 * prints every argument/return it knows about, so that the apihook.dll log can
 * be compared byte-for-byte against what actually happened.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -o selftest.exe selftest.c
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void p(const char* what, unsigned long long v)
{
	printf("%-28s 0x%llx\n", what, v);
}

int main(int argc, char** argv)
{
	HANDLE h;
	DWORD wrote = 0, got = 0;
	BOOL ok;
	HMODULE k32;
	int n;
	char data[32];

	if (argc > 1 && !strcmp(argv[1], "dyn")) {
		HMODULE m;
		DWORD (WINAPI *ping)(void);
		DWORD t;
		m = LoadLibraryW(L"lateload.dll");
		printf("LoadLibraryW(lateload.dll) -> 0x%llx\n", (unsigned long long)(ULONG_PTR)m);
		{
			union { FARPROC raw; DWORD (WINAPI *fn)(void); } u;
			u.raw = m ? GetProcAddress(m, "lateload_ping") : NULL;
			ping = u.fn;
		}
		printf("GetProcAddress(lateload_ping) -> 0x%llx\n", (unsigned long long)(ULONG_PTR)ping);
		if (ping) {
			t = ping();
			printf("lateload_ping() -> 0x%lx\n", (unsigned long)t);
		}
		return m ? 0 : 1;
	}

	if (argc > 1 && !strcmp(argv[1], "loop")) {
		int i, iters = argc > 2 ? atoi(argv[2]) : 30;
		printf("== selftest loop pid=%lu tid=%lu iters=%d ==\n",
		       (unsigned long)GetCurrentProcessId(),
		       (unsigned long)GetCurrentThreadId(), iters);
		fflush(stdout);
		for (i = 0; i < iters; i++) {
			HANDLE fh = CreateFileW(L"selftest.tmp", GENERIC_WRITE, 0, NULL,
						CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
			DWORD w = 0;
			WriteFile(fh, "loop", 4, &w, NULL);
			CloseHandle(fh);
			printf("loop %d pid=%lu handle=0x%llx wrote=%lu\n", i,
			       (unsigned long)GetCurrentProcessId(),
			       (unsigned long long)(ULONG_PTR)fh, (unsigned long)w);
			fflush(stdout);
			Sleep(1000);
		}
		DeleteFileW(L"selftest.tmp");
		printf("== selftest loop done ==\n");
		return 0;
	}

	printf("== selftest ==\n");
	printf("pid=%lu tid=%lu\n", (unsigned long)GetCurrentProcessId(),
	       (unsigned long)GetCurrentThreadId());
	p("buf_wrote", (unsigned long long)(ULONG_PTR)&wrote);
	p("buf_data", (unsigned long long)(ULONG_PTR)data);
	p("buf_got", (unsigned long long)(ULONG_PTR)&got);
	p("k32name", (unsigned long long)(ULONG_PTR)L"kernel32.dll");
	p("path_selftest_tmp", (unsigned long long)(ULONG_PTR)L"selftest.tmp");

	DeleteFileW(L"selftest.tmp");
	h = CreateFileW(L"selftest.tmp", GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
			FILE_ATTRIBUTE_NORMAL, NULL);
	p("CreateFileW#1_ret", (unsigned long long)(ULONG_PTR)h);
	ok = WriteFile(h, "hello-trace", 11, &wrote, NULL);
	p("WriteFile_ret", (unsigned long long)ok);
	p("WriteFile_wrote", (unsigned long long)wrote);
	CloseHandle(h);
	p("CloseHandle#1_ret", (unsigned long long)(ULONG_PTR)0);

	h = CreateFileW(L"selftest.tmp", GENERIC_READ, FILE_SHARE_READ, NULL,
			OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	p("CreateFileW#2_ret", (unsigned long long)(ULONG_PTR)h);
	ok = ReadFile(h, data, 11, &got, NULL);
	data[got < 31 ? got : 31] = 0;
	p("ReadFile_ret", (unsigned long long)ok);
	p("ReadFile_got", (unsigned long long)got);
	printf("ReadFile_data               \"%s\"\n", data);
	CloseHandle(h);
	DeleteFileW(L"selftest.tmp");

	k32 = GetModuleHandleW(L"kernel32.dll");
	p("GetModuleHandleW_ret", (unsigned long long)(ULONG_PTR)k32);

	n = MulDiv(7, 3, 2);
	p("MulDiv_ret", (unsigned long long)(ULONG_PTR)n);

	n = lstrlenA("hello");
	p("lstrlenA_ret", (unsigned long long)(ULONG_PTR)n);

	p("GetCurrentProcessId_ret", (unsigned long long)GetCurrentProcessId());
	p("GetCurrentThreadId_ret", (unsigned long long)GetCurrentThreadId());
	printf("== selftest done ==\n");
	return 0;
}
