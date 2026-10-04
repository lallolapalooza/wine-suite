/*
 * apihook.dll -- in-process Import Address Table tracer for Win64 programs.
 *
 * Injected with LoadLibraryW by apitrace.exe.  It scans every loaded module's
 * import directory, rewrites the IAT entries of the functions selected by a
 * config file so they point at a generated call-through stub, and logs one line
 * per call:
 *
 *     <seq> <tid> <dll>!<func> (arg0=0x..., arg1=0x...) -> 0x...
 *
 * Config grammar (notes/apitrace.md has the full spec):
 *     dll!func          hook this import (dll may be written with or without .dll)
 *     dll!*             hook every import of that DLL,  *!func and *!* also work
 *     ~dll!func         exclusion; exclusions win over inclusions
 *     dll!func@N        log N arguments (default 4, max 16; stack args included)
 *     dll!func@N:W      print only the low W bytes of the return value (4 or 8)
 *     # comment / blank lines ignored; matching is case-insensitive
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -shared -o apihook.dll apihook.c hook_common.S
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

extern void hook_common(void);                 /* hook_common.S */

typedef unsigned long long u64;

#define MAX_PATTERNS 512
#define MAX_SLOTS    32768
#define STUB_STRIDE  32
#define POOL_SIZE    (MAX_SLOTS * STUB_STRIDE) /* 1 MiB executable stub pool   */
#define BATCH        2048
#define MAX_SEEN     8192
#define NAMELEN      200

typedef struct {
	char  dll[64];
	char  func[128];
	int   excl;
	int   argc;            /* -1 = default (4), else 0..16 */
	int   retw;            /* 4 or 8 */
	int   matched;
	unsigned char amask[16];   /* bytes per argument; 8 = full register      */
	int   namask;
	char  raw[NAMELEN];
} Pattern;

typedef struct {
	char   name[NAMELEN];
	int    argc;
	int    retw;
	unsigned char amask[16];
	void** iat;
	void*  orig;
	void*  stub;
} Slot;

typedef struct {
	char   name[NAMELEN];
	int    argc;
	int    retw;
	unsigned char amask[16];
	void** iat;
	void*  orig;
} Pending;

/* --- globals -------------------------------------------------------------- */
static Pattern  g_pat[MAX_PATTERNS];
static int      g_npat;
static int      g_have_includes;
static Slot     g_slots[MAX_SLOTS];
static volatile LONG g_nslots;
static unsigned char* g_pool;
static HMODULE  g_self;
static HANDLE   g_log = INVALID_HANDLE_VALUE;
static SRWLOCK  g_lock = SRWLOCK_INIT;
static volatile LONG64 g_seq;
static DWORD    g_tls;
static int      g_poll_ms = 200;
static int      g_note_resolved;
static int      g_loader_notify;
static DWORD    g_modules;
static LONG     g_rescan_budget = 400;
static char     g_cfgpath[MAX_PATH];
static char     g_outpath[MAX_PATH];
static char     g_ready[MAX_PATH];
static char     g_dllpath[MAX_PATH];
static char     g_cfg_err[64];

static volatile LONG g_nseen;
static HMODULE  g_seen[MAX_SEEN];

static Pending* g_batch;
static int      g_nbatch;

/* --- tiny helpers --------------------------------------------------------- */
static int ci_eq(const char* a, const char* b)
{
	while (*a && *b) {
		char x = *a++, y = *b++;
		if (x >= 'A' && x <= 'Z') x += 32;
		if (y >= 'A' && y <= 'Z') y += 32;
		if (x != y) return 0;
	}
	return *a == 0 && *b == 0;
}

static int ci_has(const char* hay, const char* needle)
{
	size_t n = strlen(needle);
	if (!n) return 0;
	for (; *hay; hay++) {
		size_t i;
		for (i = 0; i < n; i++) {
			char a = hay[i], b = needle[i];
			if (!a) return 0;
			if (a >= 'A' && a <= 'Z') a += 32;
			if (b >= 'A' && b <= 'Z') b += 32;
			if (a != b) break;
		}
		if (i == n) return 1;
	}
	return 0;
}

static void trim(char** ps)
{
	char* s = *ps;
	while (*s == ' ' || *s == '\t') s++;
	{
		char* e = s + strlen(s);
		while (e > s && (e[-1] == ' ' || e[-1] == '\t')) *--e = 0;
	}
	*ps = s;
}

static void log_raw(const char* s, int len)
{
	DWORD w;
	if (g_log == INVALID_HANDLE_VALUE || len <= 0) return;
	WriteFile(g_log, s, (DWORD)len, &w, NULL);
}

static void log_fmt(const char* fmt, ...)
{
	char buf[512];
	va_list va;
	int n;
	va_start(va, fmt);
	n = _vsnprintf(buf, sizeof(buf) - 2, fmt, va);
	va_end(va);
	if (n < 0) n = (int)sizeof(buf) - 2;
	buf[n++] = '\n';
	log_raw(buf, n);
}

/* --- seen-module set ------------------------------------------------------ */
static int seen_has(HMODULE h)
{
	LONG n = InterlockedCompareExchange(&g_nseen, 0, 0), i;
	for (i = 0; i < n; i++) if (g_seen[i] == h) return 1;
	return 0;
}

static void seen_add(HMODULE h)
{
	LONG n = InterlockedIncrement(&g_nseen) - 1;
	if (n >= MAX_SEEN) { InterlockedDecrement(&g_nseen); return; }
	g_seen[n] = h;
}

/* --- config --------------------------------------------------------------- */
static void add_pattern(const char* line, const char* raw)
{
	char tmp[NAMELEN];
	char *bang, *p, *at;
	int n;
	Pattern* pt;

	if (g_npat >= MAX_PATTERNS) return;
	strncpy(tmp, line, sizeof(tmp) - 1);
	tmp[sizeof(tmp) - 1] = 0;
	p = tmp;
	pt = &g_pat[g_npat];
	memset(pt, 0, sizeof(*pt));
	pt->argc = -1;
	pt->retw = 8;
	{
		int k;
		for (k = 0; k < 16; k++) pt->amask[k] = 8;
	}
	_snprintf(pt->raw, NAMELEN - 1, "%s", raw);

	if (*p == '~') { pt->excl = 1; p++; }
	bang = strchr(p, '!');
	if (!bang) return;
	*bang = 0;
	_snprintf(pt->dll, sizeof(pt->dll) - 1, "%s", p);
	n = (int)strlen(pt->dll);
	if (n > 4 && ci_eq(pt->dll + n - 4, ".dll")) pt->dll[n - 4] = 0;
	p = bang + 1;
	at = strchr(p, '@');
	if (at) {
		char* q;
		int i;
		*at = 0;
		pt->argc = atoi(at + 1);
		if (pt->argc < 0) pt->argc = -1;
		if (pt->argc > 16) pt->argc = 16;
		q = at + 1;
		while (*q && *q != '/' && *q != ':') q++;
		if (*q == '/') {                      /* /8488448 -> per-arg widths */
			q++;
			i = 0;
			while (*q >= '1' && *q <= '8' && i < 16) {
				int w = *q - '0';
				pt->amask[i++] = (w == 1 || w == 2 || w == 4 || w == 8)
						 ? (unsigned char)w : 8;
				q++;
			}
			pt->namask = i;
		}
		if (*q == ':') pt->retw = (atoi(q + 1) == 4) ? 4 : 8;
	}
	strncpy(pt->func, p, sizeof(pt->func) - 1);
	if (!pt->excl) g_have_includes = 1;
	g_npat++;
}

static void read_config(void)
{
	HANDLE f;
	static char buf[65536];
	DWORD rd = 0;
	char* line;

	f = CreateFileA(g_cfgpath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
			NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (f == INVALID_HANDLE_VALUE) {
		_snprintf(g_cfg_err, sizeof(g_cfg_err) - 1, "cannot open cfg (%lu)", GetLastError());
		return;
	}
	ReadFile(f, buf, sizeof(buf) - 1, &rd, NULL);
	CloseHandle(f);
	buf[rd] = 0;
	line = buf;
	while (line && *line) {
		char* nl = strpbrk(line, "\r\n");
		char* cmt;
		char* s;
		if (nl) *nl = 0;
		cmt = strchr(line, '#');
		if (cmt) *cmt = 0;
		s = line;
		trim(&s);
		if (*s) add_pattern(s, line);
		line = nl ? nl + 1 : NULL;
	}
}

static int pat_dll_hit(const Pattern* p, const char* base, const char* modname)
{
	return (p->dll[0] == '*' && !p->dll[1]) || ci_eq(p->dll, base) || ci_eq(p->dll, modname);
}

static int pat_func_hit(const Pattern* p, const char* func)
{
	return (p->func[0] == '*' && !p->func[1]) || ci_eq(p->func, func);
}

/* returns 0 = this import is not wanted, else number-of-args + 1.
   Every include pattern that names a real import is flagged "matched",
   even when an exclusion then suppresses the hook. */
static int cfg_match(const char* modname, const char* func, int* retw,
		     unsigned char* amask, int* namask)
{
	char base[64];
	char* dot;
	int i, hit = 0, argc = 4;

	strncpy(base, modname, sizeof(base) - 1);
	base[sizeof(base) - 1] = 0;
	dot = strrchr(base, '.');
	if (dot) *dot = 0;

	for (i = 0; i < g_npat; i++) {
		Pattern* p = &g_pat[i];
		if (p->excl || !pat_dll_hit(p, base, modname) || !pat_func_hit(p, func)) continue;
		if (!p->matched) {
			p->matched = 1;
			if (g_note_resolved) {
				AcquireSRWLockExclusive(&g_lock);
				log_fmt("# resolved: %s  (first match %s!%s)", p->raw, modname, func);
				ReleaseSRWLockExclusive(&g_lock);
			}
		}
	}
	for (i = 0; i < g_npat; i++) {                 /* exclusions win */
		Pattern* p = &g_pat[i];
		if (!p->excl || !pat_dll_hit(p, base, modname) || !pat_func_hit(p, func)) continue;
		return 0;
	}
	for (i = 0; i < g_npat; i++) {
		Pattern* p = &g_pat[i];
		if (p->excl || !pat_dll_hit(p, base, modname) || !pat_func_hit(p, func)) continue;
		hit = 1;
		if (p->argc >= 0) argc = p->argc;
		if (retw) *retw = p->retw;
		if (amask) memcpy(amask, p->amask, 16);
		if (namask) *namask = p->namask;
	}
	return hit ? argc + 1 : 0;
}

/* --- stub generation / IAT patching --------------------------------------- */
static int our_stub(const void* p)
{
	return g_pool && (const unsigned char*)p >= g_pool &&
	       (const unsigned char*)p < g_pool + POOL_SIZE &&
	       (((const unsigned char*)p - g_pool) % STUB_STRIDE) == 0;
}

static void* make_stub(int idx, void* orig)
{
	unsigned char* s;
	if (!g_pool || idx < 0 || idx >= MAX_SLOTS) return NULL;
	s = g_pool + (SIZE_T)idx * STUB_STRIDE;
	s[0] = 0x68;                                 /* push imm32 idx          */
	*(int32_t*)(s + 1) = idx;
	s[5] = 0x49; s[6] = 0xBB;                    /* mov r11, imm64 orig     */
	*(u64*)(s + 7) = (u64)(uintptr_t)orig;
	s[15] = 0xFF; s[16] = 0x25;                  /* jmp qword ptr [rip+0]   */
	*(int32_t*)(s + 17) = 0;
	*(u64*)(s + 21) = (u64)(uintptr_t)&hook_common;
	FlushInstructionCache(GetCurrentProcess(), s, STUB_STRIDE);
	return s;
}

static void flush_batch(void)
{
	int i;
	if (g_nbatch == 0 || !g_batch) return;
	for (i = 0; i < g_nbatch; i++) {
		Pending* p = &g_batch[i];
		LONG idx;
		Slot* s;
		void* orig;
		void* stub;
		DWORD old;
		orig = *p->iat;
		if (!orig || our_stub(orig)) continue;    /* lost the race: done/empty */
		idx = InterlockedIncrement(&g_nslots) - 1;
		if (idx >= MAX_SLOTS) { InterlockedDecrement(&g_nslots); break; }
		stub = make_stub((int)idx, orig);
		if (!stub) { InterlockedDecrement(&g_nslots); continue; }
		s = &g_slots[idx];
		memcpy(s->name, p->name, NAMELEN);
		s->name[NAMELEN - 1] = 0;
		s->argc = p->argc;
		s->retw = p->retw;
		memcpy(s->amask, p->amask, 16);
		s->iat = p->iat;
		s->orig = orig;
		s->stub = stub;
		if (VirtualProtect(p->iat, sizeof(void*), PAGE_READWRITE, &old)) {
			*p->iat = stub;
			VirtualProtect(p->iat, sizeof(void*), old, &old);
		} else {
			s->stub = NULL;
			InterlockedDecrement(&g_nslots);
		}
	}
	g_nbatch = 0;
}

static void queue_hook(const char* modname, const char* func, int argc, int retw,
		       const unsigned char* amask, void** iat, void* orig)
{
	Pending* p;
	if (g_nbatch >= BATCH) flush_batch();
	p = &g_batch[g_nbatch++];
	_snprintf(p->name, NAMELEN - 1, "%s!%s", modname, func);
	p->argc = argc;
	p->retw = retw;
	memcpy(p->amask, amask, 16);
	p->iat = iat;
	p->orig = orig;
}

/* returns 1 if the module must be re-scanned later (unfilled IAT slots) */
static int scan_module(HMODULE base, const char* modname)
{
	PIMAGE_DOS_HEADER dos;
	PIMAGE_NT_HEADERS nt;
	PIMAGE_IMPORT_DESCRIPTOR imp;
	DWORD rva;
	int unfilled = 0;

	if (!base || (HMODULE)base == g_self) return 0;
	if (ci_has(modname, "apihook")) return 0;
	dos = (PIMAGE_DOS_HEADER)base;
	if (dos->e_magic != IMAGE_DOS_SIGNATURE) return 0;
	nt = (PIMAGE_NT_HEADERS)((unsigned char*)base + dos->e_lfanew);
	if (nt->Signature != IMAGE_NT_SIGNATURE) return 0;
	if (nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return 0;
	rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
	if (!rva) return 0;
	imp = (PIMAGE_IMPORT_DESCRIPTOR)((unsigned char*)base + rva);
	for (; imp->Name; imp++) {
		const char* dll = (const char*)base + imp->Name;
		PIMAGE_THUNK_DATA oft = imp->OriginalFirstThunk
			? (PIMAGE_THUNK_DATA)((unsigned char*)base + imp->OriginalFirstThunk) : NULL;
		PIMAGE_THUNK_DATA iat = (PIMAGE_THUNK_DATA)((unsigned char*)base + imp->FirstThunk);
		int i;
		if (!oft) continue;
		for (i = 0; oft[i].u1.AddressOfData; i++) {
			PIMAGE_IMPORT_BY_NAME ibn;
			const char* func;
			void* cur;
			int argc, retw = 8;
			unsigned char amask[16];
			memset(amask, 8, sizeof(amask));
			if (oft[i].u1.Ordinal & IMAGE_ORDINAL_FLAG64) continue;
			ibn = (PIMAGE_IMPORT_BY_NAME)((unsigned char*)base + oft[i].u1.AddressOfData);
			func = (const char*)ibn->Name;
			argc = cfg_match(dll, func, &retw, amask, NULL);
			if (!argc) continue;
			argc--;
			cur = (void*)iat[i].u1.Function;
			if (our_stub(cur)) continue;
			if (!cur) { unfilled = 1; continue; }
			queue_hook(dll, func, argc, retw, amask, (void**)&iat[i].u1.Function, cur);
		}
	}
	return unfilled;
}

static void scan_all_modules(void)
{
	HANDLE snap;
	MODULEENTRY32W me;
	DWORD n = 0;
	snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32,
					GetCurrentProcessId());
	if (snap == INVALID_HANDLE_VALUE) return;
	me.dwSize = sizeof(me);
	if (Module32FirstW(snap, &me)) {
		do {
			char nm[64];
			int unfilled;
			n++;
			if (seen_has((HMODULE)me.hModule)) continue;
			WideCharToMultiByte(CP_ACP, 0, me.szModule, -1, nm, sizeof(nm), NULL, NULL);
			unfilled = scan_module((HMODULE)me.hModule, nm);
			if (!unfilled || g_rescan_budget <= 0) seen_add((HMODULE)me.hModule);
			else if (InterlockedDecrement(&g_rescan_budget) <= 0) seen_add((HMODULE)me.hModule);
			if (g_nbatch >= BATCH) flush_batch();
		} while (Module32NextW(snap, &me));
	}
	g_modules = n;
	CloseHandle(snap);
}

/* --- loader notifications ------------------------------------------------- */
typedef struct { USHORT Length, MaximumLength; PWSTR Buffer; } ATR_US;
typedef struct {
	ULONG Flags;
	ATR_US* FullDllName;
	ATR_US* BaseDllName;
	PVOID DllBase;
} ATR_LOADED;
typedef struct { ATR_LOADED Loaded; } ATR_DLL_DATA;
typedef VOID (NTAPI *ATR_NOTIFY)(ULONG reason, ATR_DLL_DATA* data, PVOID ctx);
typedef LONG (NTAPI *ATR_REGISTER)(ULONG flags, ATR_NOTIFY fn, PVOID ctx, PVOID* cookie);

#define ATR_LDR_REASON_LOADED 1

static ATR_NOTIFY g_notify_fn;
static PVOID      g_notify_cookie;
static Pending    g_cb_batch[BATCH];

static VOID NTAPI on_dll_loaded(ULONG reason, ATR_DLL_DATA* data, PVOID ctx)
{
	char nm[64];
	Pending* save = g_batch;
	int save_n = g_nbatch;
	(void)ctx;
	if (reason != ATR_LDR_REASON_LOADED || !data) return;
	WideCharToMultiByte(CP_ACP, 0, data->Loaded.BaseDllName->Buffer, -1,
			    nm, sizeof(nm), NULL, NULL);
	g_batch = g_cb_batch;
	g_nbatch = 0;
	scan_module((HMODULE)data->Loaded.DllBase, nm);
	flush_batch();
	g_batch = save;
	g_nbatch = save_n;
	seen_add((HMODULE)data->Loaded.DllBase);
}

static DWORD WINAPI poll_thread(LPVOID p)
{
	(void)p;
	for (;;) {
		Sleep((DWORD)g_poll_ms);
		scan_all_modules();
		flush_batch();
	}
	return 0;
}

/* --- logging -------------------------------------------------------------- */
static int ap(char* buf, int cap, int n, const char* fmt, ...)
{
	va_list va;
	int r;
	if (n >= cap - 1) return cap - 1;
	va_start(va, fmt);
	r = _vsnprintf(buf + n, cap - n - 1, fmt, va);
	va_end(va);
	if (r < 0) return cap - 1;
	return n + r;
}

/* called from hook_common.S: (idx, a0, a1, a2, a3, retval, caller_rsp) */
void trace_emit(long long idx, u64 a0, u64 a1, u64 a2, u64 a3, u64 ret, u64 caller_rsp)
{
	Slot* s;
	u64 a[16];
	int cnt, i, n = 0;
	char buf[768];

	if (g_log == INVALID_HANDLE_VALUE) return;
	if (TlsGetValue(g_tls)) return;                /* re-entry from our logger */
	TlsSetValue(g_tls, (void*)1);
	if (idx < 0 || idx >= g_nslots) { TlsSetValue(g_tls, NULL); return; }
	s = &g_slots[idx];
	if (!s->stub) { TlsSetValue(g_tls, NULL); return; }
	cnt = s->argc < 0 ? 4 : s->argc;
	a[0] = a0; a[1] = a1; a[2] = a2; a[3] = a3;
	for (i = 4; i < cnt; i++)
		a[i] = *(u64*)(uintptr_t)(caller_rsp + 0x28 + (u64)(i - 4) * 8);

	AcquireSRWLockExclusive(&g_lock);
	n = ap(buf, sizeof(buf), n, "%llu %lu %s (",
	       (unsigned long long)InterlockedIncrement64(&g_seq),
	       (unsigned long)GetCurrentThreadId(), s->name);
	for (i = 0; i < cnt; i++) {
		unsigned char w = s->amask[i];
		u64 v = a[i];
		if (w > 0 && w < 8) v &= ((u64)1 << (w * 8)) - 1;
		n = ap(buf, sizeof(buf), n, "%sarg%d=0x%llx", i ? ", " : "", i,
		       (unsigned long long)v);
	}
	if (s->retw == 4) ret &= 0xffffffffULL;
	n = ap(buf, sizeof(buf), n, ") -> 0x%llx\n", (unsigned long long)ret);
	log_raw(buf, n);
	ReleaseSRWLockExclusive(&g_lock);
	TlsSetValue(g_tls, NULL);
}

static void write_header(void)
{
	int i, un = 0, exc = 0;
	for (i = 0; i < g_npat; i++) {
		if (g_pat[i].excl) { exc++; continue; }
		if (!g_pat[i].matched) un++;
	}
	AcquireSRWLockExclusive(&g_lock);
	log_fmt("# apitrace apihook.dll win64 pid=%lu tid=%lu",
		(unsigned long)GetCurrentProcessId(), (unsigned long)GetCurrentThreadId());
	log_fmt("# apihook=%s", g_dllpath);
	log_fmt("# cfg=%s", g_cfgpath);
	log_fmt("# out=%s", g_outpath);
	log_fmt("# patterns=%d exclusions=%d modules=%lu loader_notify=%d poll_ms=%d cfg_error=%s",
		g_npat, exc, (unsigned long)g_modules, g_loader_notify, g_poll_ms,
		g_cfg_err[0] ? g_cfg_err : "-");
	log_fmt("# unresolved_patterns=%d", un);
	for (i = 0; i < g_npat; i++) {
		Pattern* p = &g_pat[i];
		char m[20];
		int k;
		for (k = 0; k < 16; k++) m[k] = (char)('0' + p->amask[k]);
		m[16] = 0;
		log_fmt("# pattern: %s -> dll=%s func=%s argc=%d mask=%s retw=%d%s",
			p->raw, p->dll, p->func, p->argc, m, p->retw,
			p->matched ? "" : " (unresolved)");
	}
	for (i = 0; i < g_npat; i++)
		if (!g_pat[i].excl && !g_pat[i].matched) log_fmt("# unresolved: %s", g_pat[i].raw);
	for (i = 0; i < g_npat; i++)
		if (g_pat[i].excl) log_fmt("# exclude: %s", g_pat[i].raw);
	ReleaseSRWLockExclusive(&g_lock);
}

/* --- job file / init ------------------------------------------------------ */
static void read_job(void)
{
	char path[MAX_PATH];
	char jpath[MAX_PATH];
	char jbuf[8192];
	HANDLE f;
	DWORD rd = 0;
	char *p, *base;
	WCHAR wd[MAX_PATH];

	GetModuleFileNameW(g_self, wd, MAX_PATH);
	WideCharToMultiByte(CP_ACP, 0, wd, -1, g_dllpath, sizeof(g_dllpath), NULL, NULL);
	strncpy(path, g_dllpath, sizeof(path) - 1);
	path[sizeof(path) - 1] = 0;
	base = strrchr(path, '\\');
	if (base) base[1] = 0; else path[0] = 0;

	_snprintf(jpath, sizeof(jpath) - 1, "%sapitrace_%lu.job", path,
		  (unsigned long)GetCurrentProcessId());
	f = CreateFileA(jpath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
			NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (f == INVALID_HANDLE_VALUE) {
		/* no job file: fall back to defaults next to the DLL */
		_snprintf(g_cfgpath, MAX_PATH - 1, "%sapitrace.cfg", path);
		_snprintf(g_outpath, MAX_PATH - 1, "%sapitrace.log", path);
		return;
	}
	ReadFile(f, jbuf, sizeof(jbuf) - 1, &rd, NULL);
	CloseHandle(f);
	DeleteFileA(jpath);
	jbuf[rd] = 0;

	for (p = jbuf; p && *p; ) {
		char* nl = strpbrk(p, "\r\n");
		char* eq;
		if (nl) *nl = 0;
		eq = strchr(p, '=');
		if (eq) {
			char* v;
			*eq = 0;
			v = eq + 1;
			trim(&p);
			trim(&v);
			if (ci_eq(p, "cfg")) strncpy(g_cfgpath, v, MAX_PATH - 1);
			else if (ci_eq(p, "out")) strncpy(g_outpath, v, MAX_PATH - 1);
			else if (ci_eq(p, "ready")) strncpy(g_ready, v, MAX_PATH - 1);
			else if (ci_eq(p, "poll")) g_poll_ms = atoi(v);
		}
		p = nl ? nl + 1 : NULL;
	}
	if (g_poll_ms < 10) g_poll_ms = 10;
}

static DWORD WINAPI init_thread(LPVOID param)
{
	ATR_REGISTER reg;
	HANDLE t;
	(void)param;

	g_tls = TlsAlloc();
	g_batch = (Pending*)HeapAlloc(GetProcessHeap(), 0, BATCH * sizeof(Pending));
	g_pool = (unsigned char*)VirtualAlloc(NULL, POOL_SIZE,
			MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
	read_job();
	if (g_cfgpath[0]) read_config();
	else _snprintf(g_cfg_err, sizeof(g_cfg_err) - 1, "no config path");
	if (!g_have_includes) _snprintf(g_cfg_err, sizeof(g_cfg_err) - 1, "no include patterns");
	if (g_outpath[0])
		g_log = CreateFileA(g_outpath, FILE_APPEND_DATA,
				    FILE_SHARE_READ | FILE_SHARE_WRITE,
				    NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

	reg = (ATR_REGISTER)(void*)GetProcAddress(GetModuleHandleA("ntdll.dll"), "LdrRegisterDllNotification");
	if (reg) {
		g_notify_fn = on_dll_loaded;
		if (reg(0, g_notify_fn, NULL, &g_notify_cookie) == 0) g_loader_notify = 1;
	}
	scan_all_modules();          /* installs hooks + writes "resolved" notes */
	flush_batch();
	g_note_resolved = 1;
	write_header();

	t = CreateThread(NULL, 0, poll_thread, NULL, 0, NULL);
	if (t) CloseHandle(t);

	if (g_ready[0]) {
		HANDLE e = OpenEventA(EVENT_MODIFY_STATE, FALSE, g_ready);
		if (e) { SetEvent(e); CloseHandle(e); }
	}
	return 0;
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID reserved)
{
	(void)reserved;
	if (reason == DLL_PROCESS_ATTACH) {
		HANDLE t;
		g_self = hinst;
		DisableThreadLibraryCalls(hinst);
		t = CreateThread(NULL, 0, init_thread, NULL, 0, NULL);
		if (t) CloseHandle(t);
	} else if (reason == DLL_PROCESS_DETACH) {
		if (g_log != INVALID_HANDLE_VALUE) {
			AcquireSRWLockExclusive(&g_lock);
			log_raw("# process exit\n", 15);
			ReleaseSRWLockExclusive(&g_lock);
			CloseHandle(g_log);
			g_log = INVALID_HANDLE_VALUE;
		}
	}
	return TRUE;
}
