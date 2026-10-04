/*
 * lateload.dll -- helper for the apihook dynamic-hook self test.
 *
 * It is loaded at runtime by `selftest.exe dyn` and statically imports
 * winmm!timeGetTime, a function no module of a suspended selftest.exe imports.
 * A config that selects winmm!timeGetTime therefore starts out *unresolved*
 * and can only become resolvable once the loader notification (or the polling
 * fallback) has scanned this late-loaded module.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -shared -o lateload.dll lateload.c -lwinmm
 */
#include <windows.h>
#include <mmsystem.h>

__declspec(dllexport) DWORD lateload_ping(void)
{
	DWORD t = timeGetTime();
	return t;
}
