#!/bin/bash
# Capture a *scoped* WINEDEBUG=+relay trace of the Eos start-up under Wine.
#
# Wine's relay channel honours HKCU\Software\Wine\Debug\RelayInclude / RelayExclude
# (dlls/ntdll/relay.c), so the trace is limited to the start-up neighbourhood instead of
# the multi-GB firehose.  Entries are either FuncName or Module.FuncName / Module.*.
#
# usage: tools/run_eos_relay.sh <tag> [--secs N] [--include 'A,B,C'] [--debug '+sync']
#
# Result: logs/api/<tag>.relay.log (+ .stderr) with decoded string arguments.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../env.sh
source "$ROOT/env.sh"

TAG=""
SECS=25
# The relay filter patches the *exports*, so unlike the IAT tracer it also sees functions the
# app resolves with GetProcAddress (e.g. WinUsb_*).  Keep the set on the hang neighbourhood.
INCLUDE='WaitForSingleObject;WaitForMultipleObjects;CreateSemaphoreW;OpenSemaphoreA;OpenSemaphoreW;ReleaseSemaphore;CreateMutexW;OpenMutexA;CreateEventW;SetEvent;ResetEvent;InitOnceExecuteOnce;SleepConditionVariableCS;SleepConditionVariableSRW;WakeAllConditionVariable;CreateFileW;CreateFileMappingW;OpenFileMappingW;MapViewOfFile;RegOpenKeyExW;RegQueryValueExW;RegOpenKeyExA;RegQueryValueExA;WSAIoctl;socket;connect;bind;CreateNamedPipeW;CreatePipe;HidD_GetHidGuid;HidD_GetAttributes;HidD_GetPreparsedData;HidD_FreePreparsedData;HidP_GetCaps;HidD_SetFeature;SetupDiGetClassDevsW;SetupDiEnumDeviceInfo;SetupDiEnumDeviceInterfaces;SetupDiGetDeviceInterfaceDetailW;SetupDiDestroyDeviceInfoList;WinUsb_Initialize;WinUsb_Free;WinUsb_QueryDeviceInformation;WinUsb_ReadPipe;WinUsb_WritePipe;GetAdaptersAddresses;GetAdaptersInfo;GetIfTable2;NotifyIpInterfaceChange;GetTempPathW;DeviceIoControl'
EXTRA_DEBUG='+timestamp,+relay,+err'
while [ $# -gt 0 ]; do
  case "$1" in
    --secs)    SECS="$2"; shift 2 ;;
    --include) INCLUDE="${2//,/;}"; shift 2 ;;
    --debug)   EXTRA_DEBUG="$2"; shift 2 ;;
    --)        shift; break ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *)         TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || { sed -n '2,4p' "$0" >&2; exit 2; }

export WINEPREFIX=$(readlink -f "$EW_PREFIX")
export DISPLAY="$DISP"
export PATH="$(dirname "$WINEBUILD"):$PATH"
export TMPDIR="${TMPDIR:-$EW_TMP}"
D="$EW_LOGS/api"; mkdir -p "$D"
APP_DIR="$WINEPREFIX/drive_c/Program Files/ETC/EosFamily/v3/Eos"

# Eos enforces a single instance (QSharedMemory/QSystemSemaphore): a leftover instance makes
# the next launch exit in ~2 s.  Clear the prefix of any earlier Eos before capturing.
kill_eos() {
  for p in $(pgrep -f -- 'Eos.exe' 2>/dev/null); do
    grep -qa "WINEPREFIX=$WINEPREFIX" /proc/$p/environ 2>/dev/null && kill -9 "$p" 2>/dev/null
  done
  sleep 1
}

# The Debug key may carry RelayExclude/RelayFromExclude from another project; they would
# silently hide every call.  Remove them, then install only RelayInclude.
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

echo "start $(date +%T) tag=$TAG include=$INCLUDE"
kill_eos
set_relay "$INCLUDE"
# run the app directly (no tracer) so the relay thunks are visible; a short window around the hang
WDBG="$EXTRA_DEBUG,+relay" "$ROOT/tools/run_eos.sh" "$TAG-relay" --secs "$SECS" --iv 5 >/dev/null 2>&1
# unset the include list again
kill_eos
WINEPREFIX="$WINEPREFIX" "$WINEBUILD" reg delete 'HKEY_CURRENT_USER\Software\Wine\Debug' /v RelayInclude /f >/dev/null 2>&1
mv -f "$EW_LOGS/runs/$TAG-relay/app.stderr" "$D/$TAG.relay.log" 2>/dev/null
cp -f "$EW_LOGS/runs/$TAG-relay/out.txt" "$D/$TAG.relay.out.txt" 2>/dev/null
wc -l "$D/$TAG.relay.log" 2>/dev/null
echo "end $(date +%T)"
