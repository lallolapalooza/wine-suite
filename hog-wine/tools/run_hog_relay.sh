#!/bin/bash
# Capture a *scoped* WINEDEBUG=+relay trace of the Hog PC start-up under Wine.
#
# Wine's relay channel honours HKCU\Software\Wine\Debug\RelayInclude / RelayExclude
# (dlls/ntdll/relay.c), so the trace is limited to the start-up neighbourhood
# instead of the multi-GB firehose.  Entries are FuncName or Module.FuncName / Module.*.
#
# Unlike the IAT tracer (which on i386 cannot report return values), relay records
# retval=..., so this log is the Wine-side failure oracle for tools/relaydiff.py.
#
# usage: tools/run_hog_relay.sh <tag> [--secs N] [--include 'A;B;C'] [--debug '+sync']
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""
SECS=40
EXE='launcher-win32-golden.exe'
EXARGS=()
INCLUDE='ntdll.NtLockFile;ntdll.NtUnlockFile;ntdll.NtFlushBuffersFile;kernel32.LockFileEx;kernel32.UnlockFileEx;kernel32.FlushFileBuffers;ws2_32.WSAIoctl;ws2_32.socket;ws2_32.connect;ws2_32.bind;ws2_32.WSAEventSelect;ws2_32.WSAEnumNetworkEvents;iphlpapi.GetAdaptersAddresses;iphlpapi.GetAdaptersInfo;iphlpapi.NotifyIpInterfaceChange;iphlpapi.NotifyAddrChange;netprofm.*;wtsapi32.WTSQuerySessionInformationW;wtsapi32.WTSGetActiveConsoleSessionId;newdev.DiInstallDriverA;newdev.DiInstallDriverW;setupapi.SetupDiGetClassDevsW;setupapi.SetupDiEnumDeviceInterfaces;setupapi.SetupDiGetDeviceInterfaceDetailW;hid.*;user32.RegisterPowerSettingNotification;user32.EnableNonClientDpiScaling;kernelbase.AppPolicyGetProcessTerminationMethod;opengl32.wglGetProcAddress;dwmapi.DwmIsCompositionEnabled'
EXTRA_DEBUG='+timestamp,+relay,+err'
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)    SECS="$2"; shift 2 ;;
    --include) INCLUDE="${2//;/;}"; shift 2 ;;
    --debug)   EXTRA_DEBUG="$2"; shift 2 ;;
    --exe)     EXE="$2"; shift 2 ;;
    --args)    IFS=' ' read -r -a EXARGS <<< "$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *)         TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,3p' "$0" >&2; exit 2; }

export WINEPREFIX=$(readlink -f "$HW_PREFIX")
D="$HW_LOGS/api"; mkdir -p "$D"

set_relay() {
  for v in RelayExclude RelayFromInclude RelayFromExclude; do
    WINEPREFIX="$WINEPREFIX" "$WINEBUILD" reg delete 'HKEY_CURRENT_USER\Software\Wine\Debug' /v "$v" /f >/dev/null 2>&1
  done
  cat > "$D/relay.reg" <<REGF
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Wine\\Debug]
"RelayInclude"="$1"
REGF
  WINEPREFIX="$WINEPREFIX" "$WINEBUILD" reg import "$D/relay.reg" >/dev/null 2>&1
}

echo "start $(date +%T) tag=$TAG secs=$SECS"
# run_hog.sh only clears instances of its own --exe; clear the whole tree too so a
# leftover launcher/server from an earlier capture cannot win the port/single-instance race.
for p in $(pgrep -f -- 'win32-golden' 2>/dev/null); do
  grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
done
sleep 2
set_relay "$INCLUDE"
# NB: run_hog.sh unsets WINEDEBUG unless --debug is given, so pass it as an option.
"$ROOT/tools/run_hog.sh" "$TAG-relay" --secs "$SECS" --iv 10 --debug "$EXTRA_DEBUG,+relay" \
    --exe "$EXE" -- "${EXARGS[@]}" >/dev/null 2>&1
WINEPREFIX="$WINEPREFIX" "$WINEBUILD" reg delete 'HKEY_CURRENT_USER\Software\Wine\Debug' /v RelayInclude /f >/dev/null 2>&1
mv -f "$HW_LOGS/runs/$TAG-relay/app.stderr" "$D/$TAG.relay.log" 2>/dev/null
cp -f "$HW_LOGS/runs/$TAG-relay/out.txt" "$D/$TAG.relay.out.txt" 2>/dev/null
wc -l "$D/$TAG.relay.log" 2>/dev/null
echo "end $(date +%T)"
