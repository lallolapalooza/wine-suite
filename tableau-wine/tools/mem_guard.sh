#!/bin/bash
# Memory guard: enforce a hard ceiling on host RAM use by killing *build* processes when it is crossed.
#
# Why: this host has 30 GB, ~8 GB of which is the Windows VM and several GB of Power BI/WebView2 when the app is
# running. A Wine compile job is ~1.5-2 GB RSS, and a build that runs with one job per core (22 here) reaches 30-40 GB
# on its own. That OOM-killed the session twice. Job-count defaults in tools/build_wine.sh and wine/build-clean.sh are
# now 6, but an agent can bypass a script, so the ceiling is enforced independently here.
#
# Policy: when used RAM exceeds the cap, kill the heaviest *compiler* processes first (cc1/cc1plus/ld/gcc/make), oldest
# heaviest first. Never touch qemu (the Windows VM), PBIDesktop/msmdsrv/CrRenderer (the running app), or the harness's
# own processes - killing those destroys work that cannot be resumed, whereas a killed build is just re-run.
#
# usage: mem_guard.sh [cap_percent] [interval_seconds] [--once]
#   default cap 85 (i.e. 25.5 GB of 30; the operator raised it from 80 deliberately, to leave room for one Power BI
#   run plus the VM while keeping a hard ceiling), interval 5 s. Logs to logs/mem-guard.log.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
CAP=${1:-85}
INTERVAL=${2:-5}
ONCE=${3:-}
LOG=$ROOT/logs/mem-guard.log
mkdir -p "$ROOT/logs"

used_pct() {  # integer percent of MemTotal in use, from /proc/meminfo (no external tools, no locale surprises)
    awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if (t>0) printf "%d", (t-a)*100/t}' /proc/meminfo
}

kill_builds() {
    # Candidates by name, heaviest first. `pgrep -f` is deliberately NOT used for the kill list: it matches command
    # lines and would catch an unrelated process that merely mentions "make" in its arguments.
    local sig=$1 killed=0 pid rss
    for name in cc1plus cc1 ld gcc g++ make ninja cmake; do
        for pid in $(pgrep -x "$name" 2>/dev/null); do
            rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null)
            [ -n "${rss:-}" ] || continue
            kill -"$sig" "$pid" 2>/dev/null && {
                killed=$((killed + 1))
                echo "$(date -Is)  killed $name pid=$pid rss=$((rss / 1024))MB (used=$(used_pct)%)" >> "$LOG"
            }
        done
    done
    [ "$killed" -gt 0 ] && echo "$(date -Is)  killed $killed build process(es)" >> "$LOG"
    return 0
}

while :; do
    p=$(used_pct)
    if [ "${p:-0}" -ge "$CAP" ]; then
        echo "$(date -Is)  ALERT used=${p}% >= cap=${CAP}% - reclaiming from build processes" >> "$LOG"
        kill_builds TERM
        sleep 2
        p=$(used_pct)
        # Still over? The build did not release, so take it out properly.
        if [ "${p:-0}" -ge "$((CAP + 3))" ]; then
            echo "$(date -Is)  still used=${p}% - escalating to SIGKILL" >> "$LOG"
            kill_builds KILL
        fi
    fi
    [ "$ONCE" = "--once" ] && { echo "$(date -Is)  used=${p}% (single check)"; exit 0; }
    sleep "$INTERVAL"
done
