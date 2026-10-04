# Media Foundation coverage in patched Wine 11.18 for Arena.exe

Tree: `/home/asdf/projects/resolume-wine/wine/wine-11.18`
All file:line values are from that tree. Classification: **real** = functional
implementation, **stub** = returns E_NOTIMPL / no-op, **missing** = not present.

## 1. The 12 imported entry points

### MF.dll (dlls/mf)

| Function | .spec export | Implementation | Verdict |
|---|---|---|---|
| MFCreateTopology | `mf.spec:66 @ stdcall MFCreateTopology(ptr)` | `dlls/mf/topology.c:897` | **real** |
| MFGetService | `mf.spec:78 @ stdcall MFGetService(ptr ptr ptr ptr)` | `dlls/mf/main.c:894` | **real** |
| MFCreateMediaSession | `mf.spec:45 @ stdcall MFCreateMediaSession(ptr ptr)` | `dlls/mf/session.c:5088` | **real** |
| MFCreateTopologyNode | `mf.spec:67 @ stdcall MFCreateTopologyNode(long ptr)` | `dlls/mf/topology.c:1815` | **real** |
| MFCreateSampleGrabberSinkActivate | `mf.spec:57 @ stdcall MFCreateSampleGrabberSinkActivate(ptr ptr ptr)` | `dlls/mf/samplegrabber.c:1543` | **real** |

### MFPlat.DLL (dlls/mfplat)

| Function | .spec export | Implementation | Verdict |
|---|---|---|---|
| MFCreateAttributes | `mfplat.spec:45 @ stdcall MFCreateAttributes(ptr long)` | `dlls/mfplat/main.c:3353` | **real** |
| MFPutWorkItemEx | `mfplat.spec:144 @ stdcall MFPutWorkItemEx(long ptr)` | `dlls/mfplat/queue.c:79` | **real** (delegates) |
| MFCreateSourceResolver | `mfplat.spec:71 @ stdcall MFCreateSourceResolver(ptr)` | `dlls/mfplat/main.c:6847` | **real** |
| MFCreateMediaType | `mfplat.spec:62 @ stdcall MFCreateMediaType(ptr)` | `dlls/mfplat/mediatype.c:1536` | **real** |
| MFStartup | `mfplat.spec:159 @ stdcall MFStartup(long long)` | `dlls/mfplat/main.c:1591` | **real** (delegates) |
| MFShutdown | `mfplat.spec:158 @ stdcall MFShutdown()` | `dlls/mfplat/main.c:1609` | **real** (delegates) |
| MFCreateAsyncResult | `mfplat.spec:44 @ stdcall MFCreateAsyncResult(ptr ptr ptr ptr) rtworkq.RtwqCreateAsyncResult` | forwarded to `dlls/rtworkq/queue.c:1240` | **real** |

Note: every one of the 12 is exported as `@ stdcall` (not `@ stub`). In Wine,
`@ stub` entries generate a no-op thunk; none of these 12 are stubs.

Note: `mf.spec` re-exports one of these by forwarding, so it resolves through
the same implementation:
- `mf.spec:63 @ stdcall MFCreateSourceResolver(ptr) mfplat.MFCreateSourceResolver`

### Evidence commands / observed output

```
$ grep -rn "MFCreateTopology\|MFGetService\|MFCreateMediaSession\|MFCreateTopologyNode\|MFCreateSampleGrabberSinkActivate" dlls/mf/*.c
mf/topology.c:897:HRESULT WINAPI MFCreateTopology(IMFTopology **topology)
mf/topology.c:1815:HRESULT WINAPI MFCreateTopologyNode(MF_TOPOLOGY_TYPE node_type, IMFTopologyNode **node)
mf/session.c:5088:HRESULT WINAPI MFCreateMediaSession(IMFAttributes *config, IMFMediaSession **session)
mf/main.c:894:HRESULT WINAPI MFGetService(IUnknown *object, REFGUID service, REFIID riid, void **obj)
mf/samplegrabber.c:1543:HRESULT WINAPI MFCreateSampleGrabberSinkActivate(IMFMediaType *media_type, IMFSampleGrabberSinkCallback *callback, IMFActivate **activate)
```

```
$ grep -rn "MFCreateAttributes\|MFPutWorkItemEx\|MFCreateSourceResolver\|MFCreateMediaType\|MFStartup\|MFShutdown\|MFCreateAsyncResult" dlls/mfplat/*.c
mfplat/queue.c:79:HRESULT WINAPI MFPutWorkItemEx(DWORD queue, IMFAsyncResult *result)
mfplat/mediatype.c:1536:HRESULT WINAPI MFCreateMediaType(IMFMediaType **media_type)
mfplat/main.c:1591:HRESULT WINAPI MFStartup(ULONG version, DWORD flags)
mfplat/main.c:1609:HRESULT WINAPI MFShutdown(void)
mfplat/main.c:3353:HRESULT WINAPI MFCreateAttributes(IMFAttributes **attributes, UINT32 size)
mfplat/main.c:6847:HRESULT WINAPI MFCreateSourceResolver(IMFSourceResolver **resolver)
```

Bodies confirming real work (not stubs):

`MFCreateTopology` (topology.c:897):
```c
HRESULT WINAPI MFCreateTopology(IMFTopology **topology)
{
    if (!topology) return E_POINTER;
    return create_topology(topology_generate_id(), topology);
}
```

`MFCreateMediaSession` (session.c:5088) allocates a full session object and
creates a topology, event queue, presentation clock and system time source
(`MFCreateTopology`, `MFCreateEventQueue`, `MFCreatePresentationClock`,
`MFCreateSystemTimeSource` all succeed-or-fail, no E_NOTIMPL).

`MFCreateSampleGrabberSinkActivate` (samplegrabber.c:1543) builds a real
activation object holding the media type + callback context.

`MFStartup` / `MFShutdown` (main.c:1591/1609) validate the version
(`MF_VERSION_XP`/`MF_VERSION_WIN7`) and call `RtwqStartup()` / `RtwqShutdown()`.

`MFPutWorkItemEx` (queue.c:79) does `return RtwqPutWorkItem(queue, 0, (IRtwqAsyncResult *)result);`.

`MFCreateAsyncResult` is a forward in mfplat.spec:
```
$ grep -n MFCreateAsyncResult dlls/mfplat/mfplat.spec
44:@ stdcall MFCreateAsyncResult(ptr ptr ptr ptr) rtworkq.RtwqCreateAsyncResult
$ grep -n "RtwqCreateAsyncResult" dlls/rtworkq/rtworkq.spec dlls/rtworkq/queue.c
rtworkq/rtworkq.spec:9:@ stdcall RtwqCreateAsyncResult(ptr ptr ptr ptr)
rtworkq/queue.c:1240:HRESULT WINAPI RtwqCreateAsyncResult(IUnknown *object, IRtwqAsyncCallback *callback, IUnknown *state,
```
`RtwqCreateAsyncResult` calls `create_async_result(...)` (real object construction).

## 2. Sample-grabber sink: does it deliver samples?

**Yes — real delivery.** `dlls/mf/samplegrabber.c` implements a full stream sink.
`sample_grabber_stream_ProcessSample` (line 419) locks each `IMFSample`, converts
it to a contiguous buffer and invokes the user callback:

```
$ sed -n '341,350p' dlls/mf/samplegrabber.c
                hr = IMFSampleGrabberSinkCallback2_OnProcessSampleEx(...);
            else
                hr = IMFSampleGrabberSinkCallback_OnProcessSample(grabber->callback, &major_type, flags, sample_time,
                            sample_duration, data, size);
```
(`sample_grabber_report_sample`, samplegrabber.c:310; `*sample_delivered = TRUE`
is set before the callback.) Sink states, markers, sample scheduling/clock
handling and async callbacks are all implemented. Verdict: **real, delivers
samples to the `IMFSampleGrabberSinkCallback`**.

Caveat: this Wine implementation is pure media-type pass-through; it does not
itself decode. It hands the callback the raw bytes of whatever was pushed into
the sink.

## 3. H.264 decoder MFT

**Present and real, but it is a GStreamer bridge.**

- `dlls/msmpeg2vdec/msmpeg2vdec.c:32` handles `CLSID_MSH264DecoderMFT`; its
  `DllRegisterServer` (line 64) registers `"Microsoft H264 Video Decoder MFT"`
  (`MFT_CATEGORY_VIDEO_DECODER`, input H264/H264_ES → output NV12/YV12/IYUV/I420/YUY2).
- The factory `h264_decoder_factory` (`dlls/wmvdecod/video_decoder.c:42`)
  `CoCreateInstance`s `CLSID_wg_h264_decoder`
  `{1f1e273d-12c0-4b3a-8e9b-1933c2498aea}` (video_decoder.c:26-30).
- That CLSID is served by `winegstreamer`:
  `dlls/winegstreamer/mfplat.c:125,137` maps it to `h264_decoder_create`
  (`dlls/winegstreamer/video_decoder.c:1701`).
- `h264_decoder_create` calls `check_video_transform_support(...)`; on failure it
  logs `"GStreamer doesn't support H.264 decoding, please install appropriate plugins"`
  (video_decoder.c:1721) and returns the error. So availability depends on the
  host having the GStreamer H.264 decoder plugin (e.g. `avdec_h264`/`gst-libav`)
  installed at runtime; the fallback path is an error, **not** a stub.

`msmpeg2vdec.spec:1` has `@ stub GetH264DecoderFunctionTable` — but that is a
different export (function-table helper), not the MFT entry point. The MFT
itself is real.

Verdict: **H.264 decoder MFT present (`CLSID_MSH264DecoderMFT`), real but
GStreamer-backed; requires GStreamer H.264 plugins on the host.**

There is also an H.264 *encoder* MFT (`mfh264enc`, `CLSID_MSH264EncoderMFT`) —
not needed for decode.

## 4. Color Converter DSP / Video Processor MFT

Both are present as separate Wine DLLs with real swscale-based transforms.

- **Color Converter DSP — `CLSID_CColorConvertDMO`: present, real.**
  - `dlls/colorcnv/colorcnv.c:64` `DllGetClassObject` returns
    `color_converter_factory` for `CLSID_CColorConvertDMO`.
  - `dlls/colorcnv/colorcnv.c:167` registers it as MFT (`"Color Converter MFT"`,
    `MFT_CATEGORY_VIDEO_EFFECT`) and line 172 as a DMO
    (`DMORegister(L"Color Converter DMO", &CLSID_CColorConvertDMO, ...)`).
  - Real transform in `dlls/colorcnv/color_converter.c:399` uses
    `sws_scale_frame`; `transform_ProcessOutput` at color_converter.c:977
    routes to `IMediaObject_ProcessOutput`. (A handful of optional
    `IMFAttributes`/`GetInputStatus` helpers return E_NOTIMPL, color_converter.c:929-952,1276,
    but the DMO/MFT processing path is implemented.)
- **Video Processor MFT — `CLSID_VideoProcessorMFT`: present, real.**
  - `dlls/msvproc/msvproc.c:47` `DllGetClassObject` returns
    `video_processor_factory` for `CLSID_VideoProcessorMFT`; line 116 registers
    `"Microsoft Video Processor MFT"` (`MFT_CATEGORY_VIDEO_PROCESSOR`).
  - Real transform in `dlls/msvproc/video_processor.c:358` uses
    `sws_scale_frame`; `video_processor_ProcessOutput` at video_processor.c:1090
    is implemented (with D3D/DXGI device-manager paths around lines 1004-1214).

Build wiring confirms both are compiled:
```
$ grep -n "colorcnv\|msvproc" configure.ac
configure.ac:2553:WINE_CONFIG_MAKEFILE(dlls/colorcnv)
configure.ac:3053:WINE_CONFIG_MAKEFILE(dlls/msvproc)
```

Verdict: **Color Converter DSP (`CLSID_CColorConvertDMO`) and Video Processor
MFT (`CLSID_VideoProcessorMFT`) are both present and functionally implemented
(libswscale-backed).**

## 5. Summary

- All 12 imported MF/MFPlat entry points are exported as real `stdcall`
  functions (or forwards to real implementations); **none is a stub or missing**.
- Sample-grabber sink: real, delivers samples via `OnProcessSample`.
- H.264 decoder MFT: present (`CLSID_MSH264DecoderMFT`) but delegates to
  winegstreamer/GStreamer; needs host GStreamer H.264 plugins.
- Color Converter DSP and Video Processor MFT: both present, both real
  (libswscale).

Residual risk for Arena is therefore not "missing Media Foundation symbols" but
runtime dependency on GStreamer plugins (H.264 decode) and on the swscale-based
transforms accepting the exact media types Arena negotiates.

[INFERENCE] The swscale-based Color Converter / Video Processor coverage is
broad (YV12/YUY2/UYVY/AYUV/NV12/NV11/I420/IYUV/RGB*) but not exhaustively
verified against Arena's specific negotiated types here.
