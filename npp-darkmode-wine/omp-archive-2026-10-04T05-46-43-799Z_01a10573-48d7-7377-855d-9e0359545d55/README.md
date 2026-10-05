# Session archive

Generated 2026-10-04T06:52:30.852Z from session `01a10573-48d7-7377-855d-9e0359545d55`.

## Layout

| Path | Contents |
| --- | --- |
| `manifest.json` | Index of everything below (counts, sizes, subagent list) |
| `session.jsonl` | The main session transcript, verbatim |
| `agents.json` | Live per-agent state captured while the session ran (model, system prompt, tools) |
| `jobs.json` | Background jobs: `completed` (recovered from transcripts) + `live` (running/recent at archive time) |
| `artifacts/` | Every file under the session artifact directory, verbatim |
| `viewer.html` | Standalone HTML viewer (all subagent sessions embedded) |

`artifacts/` is the important part: it holds each subagent's own
`<AgentId>.jsonl` transcript (recursively nested), the session's
`*.bash.log` / `*.eval.log` / `*.read.log` files with the **full, untruncated**
tool and background-job output, and `*.jsonl.tombstone` kill markers.

## Background jobs

7 completed jobs recovered from the transcripts (main + every subagent); full list in `jobs.json`. A live snapshot of running/recent jobs for Main is also included. Per-job output lives in the owning transcript and in `artifacts/*.log`.

## Subagents (0)

_No subagent sessions were recorded for this session._

## Totals

8 files, 6469073 bytes.
