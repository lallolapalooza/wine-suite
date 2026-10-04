# FFmpeg DLL analysis (Resolume Arena 7.28 payload)

Slice: `installer/media_x/app/{avcodec-61,avutil-59,avformat-61,swscale-8}.dll`
All measurements below are from commands run in this session on those exact files, and on the
patched Wine tree `/home/asdf/projects/resolume-wine/wine/wine-11.18`.

---

## 1. FFmpeg version + verbatim build configuration

Version banner (present in avcodec/avutil/avformat; swscale has no banner string):

```
$ for f in avcodec-61 avutil-59 avformat-61 swscale-8; do grep -a -o 'FFmpeg version 7\.1\.1' $f.dll | head -1; done
avcodec-61: FFmpeg version 7.1.1
avutil-59:  FFmpeg version 7.1.1
avformat-61: FFmpeg version 7.1.1
swscale-8:
```

Source path baked into the binaries (vcpkg build tree) pins the exact tag/commit:
`n7.1.1-60170edb78.clean` (= FFmpeg n7.1.1, vcpkg ref `60170edb78`).

Version numbers:
```
$ grep -a -o 'Lavc61\.19\.101' avcodec-61.dll | head -1
Lavc61.19.101          # libavcodec 61.19.101  => avcodec-61.dll
```
Libraries are `--enable-shared` (`avcodec-61.dll`, `avutil-59.dll`, `avformat-61.dll`, `swscale-8.dll`).

The `avutil_configuration()` / `avcodec_configuration()` string is embedded **identically in all
four DLLs** — the exact same 1866-byte C string (verified by hashing):

```
$ python3 -c "...d.find(b'--prefix=')... e=d.find(b'\x00',i); sha256(d[i:e])..."
avcodec-61.dll 1866 25693251cc7c7f19
avutil-59.dll  1866 25693251cc7c7f19
avformat-61.dll 1866 25693251cc7c7f19
swscale-8.dll  1866 25693251cc7c7f19
```

### Full configuration line (verbatim)

```
--prefix='C:/GitLab-Runner/builds/yzi91zKA4/0/resolume/software/vcpkg/packages/ffmpeg_x64-windows' --toolchain=msvc --enable-pic --disable-doc --enable-debug --enable-runtime-cpudetect --disable-autodetect --target-os=win32 --enable-w32threads --enable-d3d11va --enable-d3d12va --enable-dxva2 --enable-mediafoundation --disable-inline-asm --cc=cl.exe --host_cc=cl.exe --cxx=cl.exe --windres=rc.exe --ld=link.exe --ar='ar-lib lib.exe' --ranlib=':' --enable-ffmpeg --disable-ffplay --enable-ffprobe --enable-avcodec --disable-avdevice --enable-avformat --enable-avfilter --disable-postproc --disable-swresample --enable-swscale --disable-alsa --enable-amf --disable-libaom --disable-libass --disable-avisynth --disable-bzlib --disable-libdav1d --disable-libfdk-aac --disable-libfontconfig --disable-libharfbuzz --disable-libfreetype --disable-libfribidi --disable-iconv --disable-libilbc --disable-lzma --disable-libmp3lame --disable-libmodplug --enable-cuda --enable-nvenc --enable-nvdec --enable-cuvid --enable-ffnvcodec --disable-opencl --disable-opengl --disable-libopenh264 --disable-libopenjpeg --disable-libopenmpt --disable-openssl --enable-schannel --disable-libopus --disable-sdl2 --disable-libsnappy --disable-libsoxr --disable-libspeex --disable-libssh --disable-libtensorflow --disable-libtesseract --disable-libtheora --disable-libvorbis --disable-libvpx --disable-libwebp --disable-libx264 --disable-libx265 --disable-libxml2 --enable-zlib --disable-libsrt --disable-libmfx --enable-cross-compile --disable-static --enable-shared --extra-cflags='-DHAVE_UNISTD_H=0' --pkg-config='C:/GitLab-Runner/vcpkg-downloads/tools/msys2/21caed2f81ec917b/mingw64/bin/pkg-config.exe' --enable-optimizations --extra-ldflags='-libpath:C:/GitLab-Runner/builds/yzi91zKA4/0/resolume/software/build/vcpkg_installed/x64-windows/lib' --arch=x86_64 --enable-asm --enable-x86asm
```

Extraction command used (reads the C string at its NUL terminator; the file contains exactly one
`--prefix=` configuration string per DLL):

```
$ grep -a -o -E '[^[:cntrl:]]*--enable-avcodec[^[:cntrl:]]*' avcodec-61.dll
$ python3 -c "d=open('avcodec-61.dll','rb').read(); i=d.find(b'--prefix='); e=d.find(b'\x00',i); print(d[i:e].decode())"
```

---

## 2. Windows-backend `--enable-*` flags from that line

**Enabled (Windows/hardware backends and toolchain):**

| flag | meaning |
|---|---|
| `--target-os=win32` | Windows target |
| `--toolchain=msvc` / `--cc=cl.exe --ld=link.exe` | MSVC toolchain |
| `--enable-w32threads` | Win32 threads (not pthreads) |
| `--enable-d3d11va` | D3D11VA hwaccel (decode via d3d11.dll) |
| `--enable-d3d12va` | D3D12VA hwaccel (d3d12.dll) |
| `--enable-dxva2` | DXVA2 hwaccel (dxva2.dll) |
| `--enable-mediafoundation` | Media Foundation hwaccel (mfplat.dll) |
| `--enable-schannel` | TLS via SChannel (secur32.dll), replaces OpenSSL |
| `--enable-cuda` | CUDA hwaccel (nvcuda.dll) |
| `--enable-nvenc` | NVIDIA NVENC encode (nvEncodeAPI64.dll) |
| `--enable-nvdec` | NVDEC decode |
| `--enable-cuvid` | CUVID decoder (nvcuvid.dll) |
| `--enable-ffnvcodec` | ffnvcodec headers (nvEncodeAPI/cuvid) |
| `--enable-amf` | AMD AMF (amfrt64.dll) |
| `--enable-asm` `--enable-x86asm` | external YASM/NASM asm (`--disable-inline-asm`, MSVC) |
| `--enable-runtime-cpudetect` / `--enable-optimizations` | runtime CPU dispatch |
| `--enable-shared` | DLLs |
| `--enable-debug` | debug build |

**Explicitly disabled / absent (relevant to Windows graphics):**

- `--disable-opengl` → **no OpenGL/wgl path** (also no `opengl32` import; see §5).
- `--disable-opencl`, `--disable-openssl`, `--disable-libmfx` (Intel QSV), `--disable-libopenh264`, `--disable-sdl2`, `--disable-libaom`, `--disable-libdav1d`, `--disable-libvpx`, `--disable-libx264`, `--disable-libx265`, `--disable-libssh`, `--disable-lzma`, etc.
- **No `--enable-vulkan` and no `--disable-vulkan`**: with `--disable-autodetect` Vulkan is off
  (Vulkan hwaccel not built). [INFERENCE: derived from `--disable-autodetect` + absence of any
  vulkan flag; no `vulkan` hwcontext symbol was observed in the DLLs.]

---

## 3. PE import tables (objdump -p)

Command: `objdump -p <dll> | sed -n '/The Import Tables/,/The Export Tables/p'`
(no Delay Import Tables in any of the four: `objdump -p <dll> | grep -c 'Delay Import Tables'` → 0).

### avcodec-61.dll
```
DLL Name: avutil-59.dll
DLL Name: ole32.dll            CoInitializeEx, CoUninitialize, CoTaskMemFree
DLL Name: KERNEL32.dll         (37 funcs; LoadLibraryExA/W, GetProcAddress, GetSystemDirectoryW,
                                InitializeConditionVariable, WakeAll/WakeConditionVariable,
                                SleepConditionVariableSRW, InitializeSRWLock, RtlVirtualUnwind,
                                RtlLookupFunctionEntry, RtlCaptureContext, QueryPerformanceCounter,
                                IsProcessorFeaturePresent, …)
DLL Name: VCRUNTIME140.dll     memcpy, memmove, memset, memcmp, memchr, strchr, strstr, wcsrchr,
                               __C_specific_handler, __std_type_info_destroy_list
DLL Name: api-ms-win-crt-runtime-l1-1-0.dll
DLL Name: api-ms-win-crt-stdio-l1-1-0.dll
DLL Name: api-ms-win-crt-math-l1-1-0.dll
DLL Name: api-ms-win-crt-string-l1-1-0.dll
DLL Name: api-ms-win-crt-convert-l1-1-0.dll
DLL Name: api-ms-win-crt-utility-l1-1-0.dll
DLL Name: api-ms-win-crt-heap-l1-1-0.dll
DLL Name: api-ms-win-crt-time-l1-1-0.dll
```
**No** d3d11/dxgi/d3d12/dxva2/mfplat/secur32 in the import table. These are `LoadLibrary`-time
dependencies. DLL-name strings found inside avcodec-61.dll:
`mfplat.dll`, `nvcuda.dll`, `nvcuvid.dll`, `nvEncodeAPI64.dll`, `amfrt64.dll`.
Resolved via `GetProcAddress` from those modules, e.g. literal strings:
`MFCreateMediaType`, `MFCreateSample`, `MFCreateAlignedMemoryBuffer`, `MFStartup`, `MFShutdown`,
`MFTEnumEx`, `AMFInit`, `AMFQueryVersion`, `NvEncodeAPICreateInstance`,
`NvEncodeAPIGetMaxSupportedVersion`, `cuInit`, `cuCtxCreate_v2`, `cuDeviceGet`, `cuvidCreateDecoder`,
`cuvidParseVideoData`, `cuvidMapVideoFrame64`, …

### avutil-59.dll
```
DLL Name: USER32.dll           GetDesktopWindow
DLL Name: bcrypt.dll           BCryptOpenAlgorithmProvider, BCryptCloseAlgorithmProvider, BCryptGenRandom
DLL Name: KERNEL32.dll         (49 funcs; incl. LoadLibraryA/ExA/ExW, GetProcAddress, GetSystemDirectoryW,
                                CreateFileMappingA, MapViewOfFile, CreateMutexA, GetStdHandle,
                                GetConsoleMode, WriteConsoleW, InitializeConditionVariable, …)
DLL Name: VCRUNTIME140.dll     memcpy/memmove/memset/memcmp/memchr/strchr/strrchr/strstr/wcsrchr,
                               __C_specific_handler, __std_type_info_destroy_list
DLL Name: api-ms-win-crt-runtime-l1-1-0.dll
DLL Name: api-ms-win-crt-math-l1-1-0.dll
DLL Name: api-ms-win-crt-stdio-l1-1-0.dll
DLL Name: api-ms-win-crt-string-l1-1-0.dll
DLL Name: api-ms-win-crt-time-l1-1-0.dll
DLL Name: api-ms-win-crt-convert-l1-1-0.dll
DLL Name: api-ms-win-crt-filesystem-l1-1-0.dll
DLL Name: api-ms-win-crt-heap-l1-1-0.dll
DLL Name: api-ms-win-crt-environment-l1-1-0.dll
DLL Name: api-ms-win-crt-utility-l1-1-0.dll
```
hwaccel DLL-name literals in avutil-59.dll:
`d3d11.dll`, `dxgi.dll`, `dxgidebug.dll`, `d3d12.dll`, `d3d9.dll`, `dxva2.dll`, `nvcuda.dll`.
Function literals: `D3D11CreateDevice`, `CreateDXGIFactory`, `CreateDXGIFactory1`,
`CreateDXGIFactory2`, `DXGIGetDebugInterface` (looked up in **dxgidebug.dll** — see context dump),
`D3D12CreateDevice`, `D3D12GetDebugInterface`, `Direct3DCreate9`, `Direct3DCreate9Ex`,
`DXVA2CreateDirect3DDeviceManager9`, plus the full `cu*` / CUDA list.
(Note: `strings` shows `Ad3d11.dll`; raw dump proves the 'A' is the last byte of a preceding GUID
constant in `.rdata`, so the literal is `d3d11.dll`:
`...9e de fe 40 88 06 88 f9 0c 12 b4 41 64 33 64 31 31 2e 64 6c 6c 00` → `d3d11.dll\0`.)

### avformat-61.dll
```
DLL Name: avcodec-61.dll
DLL Name: avutil-59.dll
DLL Name: Secur32.dll          AcquireCredentialsHandleA, FreeCredentialsHandle, InitializeSecurityContextA,
                               DeleteSecurityContext, QueryContextAttributesA, ApplyControlToken,
                               EncryptMessage, DecryptMessage, FreeContextBuffer
DLL Name: WS2_32.dll           getnameinfo, getaddrinfo, freeaddrinfo + 25 ordinals
DLL Name: KERNEL32.dll         (30 funcs)
DLL Name: VCRUNTIME140.dll
DLL Name: api-ms-win-crt-* (stdio, convert, string, runtime, time, math, utility, filesystem, heap, environment)
```
The 25 ordinal-only WS2_32 imports map onto Wine's ordinal numbers 1,2,3,4,5,6,7,9,10,13,14,15,16,
17,18,19,20,21,22,23,57,111,115,116,151:
`accept, bind, closesocket, connect, getpeername, getsockname, getsockopt, htons, ioctlsocket,
listen, ntohl, ntohs, recv, recvfrom, select, send, sendto, setsockopt, shutdown, socket,
gethostname, WSAGetLastError, WSAStartup, WSACleanup, __WSAFDIsSet`.

### swscale-8.dll
```
DLL Name: avutil-59.dll
DLL Name: KERNEL32.dll         (17 funcs)
DLL Name: VCRUNTIME140.dll     memcpy, memmove, memset, memcmp, __C_specific_handler,
                               __std_type_info_destroy_list
DLL Name: api-ms-win-crt-runtime-l1-1-0.dll
DLL Name: api-ms-win-crt-math-l1-1-0.dll
```
No Windows graphics/network imports at all.

---

## 4. Cross-check of imports against Wine 11.18 specs

Wine tree: `/home/asdf/projects/resolume-wine/wine/wine-11.18/dlls/`.
Method: each imported name was matched (word-boundary) against the corresponding
`dlls/<name>/<name>.spec`. `api-ms-win-crt-*` resolve through
`dlls/apisetschema/apisetschema.spec`, where every one of them is declared as
`apiset api-ms-win-crt-*-l1-1-0 = ucrtbase.dll`, so they were checked against
`dlls/ucrtbase/ucrtbase.spec`.

Result for **every function imported by the PE import tables** — all four DLLs:

```
KERNEL32.dll                  -> wine kernel32   (54 distinct imported)  MISSING: NONE
Secur32.dll                   -> wine secur32    ( 9 distinct imported)  MISSING: NONE
USER32.dll                    -> wine user32     ( 1 distinct imported)  MISSING: NONE
VCRUNTIME140.dll              -> wine vcruntime140 (11 imported)        MISSING: NONE
WS2_32.dll                    -> wine ws2_32    ( 4 named + 25 ordinals) MISSING: NONE
bcrypt.dll                    -> wine bcrypt    ( 3 imported)            MISSING: NONE
ole32.dll                     -> wine ole32     ( 3 imported)            MISSING: NONE
api-ms-win-crt-* (10 modules) -> ucrtbase        (all)                  MISSING: NONE
```

**Absent from the specs (i.e. not implemented / module missing):**

| imported symbol | target | Wine status |
|---|---|---|
| `dxgidebug.dll` | *(not a Wine module)* | **NO SPEC** — `dlls/dxgidebug/` does not exist. avutil looks up `DXGIGetDebugInterface` here (optional graphics debug layer). |
| `nvcuda.dll` | CUDA driver | **NO SPEC** — no `dlls/nvcuda/` |
| `nvcuvid.dll` | CUVID decoder | **NO SPEC** — no `dlls/nvcuvid/` |
| `nvEncodeAPI64.dll` | NVENC | **NO SPEC** — no dir |
| `amfrt64.dll` | AMD AMF runtime | **NO SPEC** — no dir |
| `DXGIGetDebugInterface` (non-`1` name) | dxgidebug.dll in FFmpeg | not present; Wine's `dxgi.spec` exposes only `DXGIGetDebugInterface1` |
| `DXGIDeclareAdapterRemovalSupport` | dxgi.dll | not present in `dxgi.spec` |

Modules that FFmpeg can dlopen and that **do** have Wine specs (functions declared, not stubs):

```
d3d11/d3d11.spec      @ stdcall D3D11CreateDevice(ptr long ptr long ptr long long ptr ptr ptr)
dxgi/dxgi.spec        @ stdcall CreateDXGIFactory(ptr ptr) / CreateDXGIFactory1 / CreateDXGIFactory2
                      @ stdcall DXGIGetDebugInterface1(long ptr ptr)
d3d12/d3d12.spec      101 stdcall D3D12CreateDevice(ptr long ptr ptr)
                      102 stdcall D3D12GetDebugInterface(ptr ptr)
                      @ stdcall D3D12SerializeVersionedRootSignature(ptr ptr ptr)
d3d9/d3d9.spec        @ stdcall Direct3DCreate9(long) / Direct3DCreate9Ex(long ptr)
dxva2/dxva2.spec      @ stdcall DXVA2CreateDirect3DDeviceManager9(ptr ptr)
mfplat/mfplat.spec    @ stdcall MFStartup(long long) / MFShutdown()
                      @ stdcall MFCreateAlignedMemoryBuffer(long long ptr) / MFCreateSample(ptr) / MFCreateMediaType(ptr)
                      @ stdcall MFTEnumEx(int128 long ptr ptr ptr ptr)
```
None of the directly-imported functions is declared as `stub` in the Wine specs (scan for
`stub` on the matching spec lines returned nothing). Absence of stubs ≠ functional completeness:
Wine's d3d11/d3d12/dxva2/mfplat implementations are partial at runtime, and SChannel's provider
set is narrower than Windows — that is a runtime behaviour question, not a spec question. [INFERENCE]

---

## 5. CRT linkage and OpenGL/wgl

- **All four DLLs dynamically link the MSVC CRT:**
  - `VCRUNTIME140.dll` is in the import table of all four (avcodec/avutil/avformat/swscale).
  - UCRT is pulled via `api-ms-win-crt-*-l1-1-0.dll` apiset DLLs (heap/stdio/string/math/…),
    which Windows and Wine redirect to `ucrtbase.dll` (Wine: `apisetschema.spec` →
    `= ucrtbase.dll`).
  - `vcruntime140_1.dll` is **not** imported; `MSVCP140*.dll` is **not** imported (no C++ runtime):
    `objdump -p <dll> | grep -iE 'msvcp|msvcr'` → no matches.
  - Build is `--enable-shared` (DLLs), so the FFmpeg libraries themselves are also dynamic —
    avcodec/avformat link `avutil-59.dll`, avformat links `avcodec-61.dll`, etc.
  - Wine 11.18 provides `dlls/vcruntime140/vcruntime140.spec`, and its three used entry points
    are forwarded to ucrtbase:
    `@ stdcall -arch=!i386 __C_specific_handler(ptr long ptr ptr) ucrtbase.__C_specific_handler`
    `@ cdecl __std_type_info_destroy_list(ptr) ucrtbase.__std_type_info_destroy_list`.
- **No OpenGL / wgl:**
  - `strings -a <dll> | grep -icE 'opengl32|wgl'` → `0` for all four.
  - `objdump -p <dll> | grep -i opengl32` → no matches for all four.
  - Consistent with `--disable-opengl` in the configuration line. (Wine does ship
    `dlls/opengl32` and `dlls/vulkan-1`, but these binaries never reference them.)

---

## Summary / Wine-relevant takeaways

1. FFmpeg **n7.1.1** (libavcodec 61.19.101), MSVC/vcpkg x64 build, `--enable-shared --enable-debug`.
2. HW backends compiled in: **d3d11va, d3d12va, dxva2, mediafoundation, schannel, cuda, nvenc,
   nvdec, cuvid, ffnvcodec, w32threads, amf**; **no vulkan, no opengl, no qsv, no openssl**.
3. The PE import tables are Windows-clean: only kernel32/user32/ole32/bcrypt/secur32/ws2_32 +
   MSVC CRT + the two FFmpeg siblings. All of those imports exist in Wine's specs (nothing stub,
   nothing missing).
4. The hardware paths are loaded at runtime. The modules Wine lacks are
   `dxgidebug.dll`, `nvcuda.dll`, `nvcuvid.dll`, `nvEncodeAPI64.dll`, `amfrt64.dll`
   (all optional hw path — FFmpeg degrades gracefully), plus `DXGIGetDebugInterface` /
   `DXGIDeclareAdapterRemovalSupport` which Wine's dxgi does not export.
5. CRT is dynamic (`VCRUNTIME140.dll` + UCRT apisets) — Wine's builtin `vcruntime140` covers all
   imported entry points. No OpenGL/wgl dependency.
