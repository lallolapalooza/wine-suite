#!/bin/bash
# Run a PowerShell command in the Windows guest through the :8000 hub.
#
# The guest poller (pbi_svc.ps1) remembers the last command text and IGNORES a repeat, so every
# command carries a unique nonce. Usage: tools/guest.sh '<powershell>' [timeout_s]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$HERE/vmcmd.sh" "& { $1 } ; \"__n=$RANDOM$(date +%s%N)\"" "${2:-90}"
