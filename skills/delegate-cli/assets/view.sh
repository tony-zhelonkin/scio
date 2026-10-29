#!/usr/bin/env bash
#
# Render a run's stream for a human: the worker's messages stand out, each command is one
# line with its outcome, and command output folds to its head, its tail and any test
# summary. codex writes text (stream.log) and pi writes JSON events (stream.jsonl); both
# render to the same layout. The stream on disk stays raw, so launch.sh, pi.sh and
# status.sh read it unchanged.

set -eu

usage() {
    echo "usage: view.sh [--follow] [--full] STREAM|UNIT" >&2
    echo "  --follow  keep rendering as the run writes (the r2-<unit>-log window)" >&2
    echo "  --full    print command output unfolded" >&2
}

follow=0
full=0
target=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --follow) follow=1; shift ;;
        --full)   full=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)       usage; exit 2 ;;
        *)        target="$1"; shift ;;
    esac
done
[ -n "$target" ] || { usage; exit 2; }

if [ ! -f "$target" ]; then
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    . "$script_dir/roots.sh"
    root=$(delegations_root "$PWD")
    run="${root:-$scratch_root}/$target/current"
    if   [ -f "$run/stream.log" ];   then target="$run/stream.log"
    elif [ -f "$run/stream.jsonl" ]; then target="$run/stream.jsonl"
    else echo "view.sh: no stream under $run" >&2; exit 2
    fi
fi

color=1
[ -z "${NO_COLOR:-}" ] || color=0
width=$(tput cols 2>/dev/null || echo 160)

render_codex() {
    awk -v color="$color" -v full="$full" -v width="$width" '
    function c(code, s) { return color ? "\033[" code "m" s "\033[0m" : s }
    function cut(s, n)  { return length(s) > n ? substr(s, 1, n - 1) "…" : s }
    function dur(ms)    { return ms < 1000 ? ms "ms" : ms < 60000 ? sprintf("%.1fs", ms / 1000) : sprintf("%dm%02ds", ms / 60000, (ms % 60000) / 1000) }
    function out(s)     { print s; fflush() }
    function signal(s)  { return s ~ /[0-9]+ (passed|failed|errors?)( |,|$)|^(FAILED|ERROR) |Traceback|Error:|^E  / }
    function shade(s)   { return s ~ /failed|FAILED|ERROR|Error|Traceback|^E  / ? c("1;31", s) : s ~ /passed/ ? c("1;32", s) : s }

    function flush_output(   i, keep_head, keep_tail, shown) {
        while (n && buf[n] == "") n--
        if (n == 0) return
        keep_head = failed ? 0 : 2
        keep_tail = failed ? 12 : 3
        for (i = 1; i <= n; i++) {
            shown = full || i <= keep_head || i > n - keep_tail
            if (shown)               out("    " c(failed ? "0" : "2", cut(buf[i], width - 4)))
            else if (signal(buf[i])) out("    " shade(cut(buf[i], width - 4)))
            else if (i == keep_head + 1) out("    " c("2;3", "… " (n - keep_head - keep_tail) " lines"))
        }
        n = 0
    }

    function cmd_line(s) {
        sub(/^\/bin\/bash -lc ./, "", s)
        if (s ~ / in \/[^ ]*$/) { here = s; sub(/^.* in /, "", here); sub(/.? in \/[^ ]*$/, "", s) }
        return s
    }

    BEGIN { mode = "head"; n = 0; pfirst = plast = npend = 0 }

    # A command that finishes after later sections reports back here, against the oldest pending command.
    match($0, /^ (succeeded|exited (-?[0-9]+)|failed) in ([0-9]+)ms:?$/, m) && mode != "exec" && mode != "head" && mode != "user" {
        flush_output()
        failed = (m[1] != "succeeded")
        late = npend ? pend[++pfirst] : "background command"
        if (npend) npend--
        verdict = failed ? c("1;31", "✗ " m[1]) : c("32", "✓")
        out("  " c("36", "↳ ") c("2;36", cut(late, width - 30)) "  " verdict " " c("2", dur(m[3] + 0)))
        mode = "output"; n = 0
        prev = $0; next
    }

    # A section starts with its marker alone on a line, after a blank line or the header rule.
    /^(user|codex|exec|thinking|file update|apply_patch)$/ && (prev == "" || prev ~ /^-+$/) || /^tokens used$/ {
        flush_output()
        if (mode == "exec" && cmd != "") { out(c("2", "  … running")); pend[++plast] = cmd; npend++ }
        mode = $0
        if (mode == "codex")        out("\n" c("1;35", "▌") " " c("1;35", "codex"))
        if (mode == "thinking")     out(c("2;3", "  thinking"))
        if (mode == "file update" || mode == "apply_patch") out(c("1;33", "  ✎ file update"))
        if (mode == "exec")         { cmd = ""; extra = 0 }
        prev = $0; next
    }

    mode == "head" {
        if ($0 ~ /^(model|reasoning effort|session id|workdir):/) {
            split($0, kv, ": "); hdr[kv[1]] = kv[2]
        }
        if ($0 == "user") mode = "user"
        prev = $0; next
    }

    mode == "user" {
        if (!shown_brief && $0 ~ /^# /) {
            out(c("1;33", "■ " hdr["model"] " · " hdr["reasoning effort"]) "  " c("1", substr($0, 3)))
            out(c("2", "  " hdr["workdir"] "  session " hdr["session id"]))
            shown_brief = 1
        }
        prev = $0; next
    }

    mode == "codex" {
        if ($0 != "") out(c("35", "▌") " " c("1", $0))
        prev = $0; next
    }

    mode == "thinking" { if ($0 != "") out("  " c("2;3", cut($0, width - 2))); prev = $0; next }

    mode == "file update" || mode == "apply_patch" {
        if      ($0 ~ /^\+/ && $0 !~ /^\+\+\+/) out("    " c("32", cut($0, width - 4)))
        else if ($0 ~ /^-/  && $0 !~ /^---/)    out("    " c("31", cut($0, width - 4)))
        else if ($0 != "")                      out("    " c("2", cut($0, width - 4)))
        prev = $0; next
    }

    mode == "exec" {
        if (match($0, /^ (succeeded|exited (-?[0-9]+)|failed) in ([0-9]+)ms:?$/, m)) {
            failed = (m[1] != "succeeded")
            tail_note = extra ? c("2", " (+" extra " lines)") : ""
            verdict = failed ? c("1;31", "✗ " m[1]) : c("32", "✓")
            out(tail_note "  " verdict " " c("2", dur(m[3] + 0)))
            mode = "output"; n = 0; cmd = ""
        } else if (cmd == "") {
            cmd = cmd_line($0)
            printf "%s", "  " c("36", "$ ") c("36", cut(cmd, width - 30)); fflush()
        } else {
            extra++
        }
        prev = $0; next
    }

    mode == "output" { buf[++n] = $0; prev = $0; next }

    mode == "tokens used" {
        if ($0 ~ /^[0-9,]+$/) { out("\n" c("1;33", "■ tokens used " $0)); mode = "done" }
        prev = $0; next
    }

    mode == "done" { next }

    END { flush_output() }
    '
}

# pi's events: an assistant message_end carries thinking, text and tool calls; a
# tool_execution_end carries the result; agent_end closes the run.
render_pi() {
    python3 -I -u -c "$PI_RENDER" "$color" "$full" "$width"
}

# The renderer is a string, so the stream stays on stdin.
PI_RENDER=$(cat <<'EOF'
import json, re, sys

color, full, width = sys.argv[1] == "1", sys.argv[2] == "1", int(sys.argv[3])

def c(code, s): return f"\033[{code}m{s}\033[0m" if color else s
def cut(s, n): return s if len(s) <= n else s[: n - 1] + "…"
def dur(ms): return f"{ms}ms" if ms < 1000 else f"{ms/1000:.1f}s" if ms < 60000 else f"{ms//60000}m{(ms%60000)//1000:02d}s"
def out(s): print(s, flush=True)
SIGNAL = re.compile(r"\d+ (passed|failed|errors?)( |,|$)|^(FAILED|ERROR) |Traceback|Error:|^E  ")
def shade(s): return c("1;31", s) if re.search(r"failed|FAILED|ERROR|Error|Traceback|^E  ", s) else c("1;32", s) if "passed" in s else s

def fold(lines, failed):
    head, tail = (0, 12) if failed else (2, 3)
    n = len(lines)
    for i, line in enumerate(lines, 1):
        if full or i <= head or i > n - tail: out("    " + c("0" if failed else "2", cut(line, width - 4)))
        elif SIGNAL.search(line): out("    " + shade(cut(line, width - 4)))
        elif i == head + 1: out("    " + c("2;3", f"… {n - head - tail} lines"))

def text_of(content):
    return "\n".join(p.get("text", "") for p in content if p.get("type") == "text")

def args_of(a):
    if "command" in a: return a["command"]
    return " ".join(str(v) for v in a.values())

shown_brief = False
calls, turns, out_tokens, peak, agy_text = 0, 0, 0, 0, ""
for line in sys.stdin:
    try: e = json.loads(line)
    except ValueError: continue
    t = e.get("type")
    if t == "message_end":
        m = e.get("message") or {}
        role = m.get("role")
        if role == "user" and not shown_brief:
            text = text_of(m.get("content") or [])
            title = next((l[2:] for l in text.splitlines() if l.startswith("# ")), text.splitlines()[0] if text else "")
            out(c("1;33", "■ pi") + "  " + c("1", cut(title, width - 6)))
            shown_brief = True
        elif role == "assistant":
            turns += 1
            u = m.get("usage") or {}
            out_tokens += u.get("output", 0); peak = max(peak, u.get("input", 0))
            if not shown_brief or turns == 1:
                out(c("2", f"  model {m.get('model', '?')}"))
            for p in m.get("content") or []:
                if p.get("type") == "thinking" and p.get("thinking"):
                    out("  " + c("2;3", "thinking"))
                    for l in p["thinking"].splitlines(): out("  " + c("2;3", cut(l, width - 2)))
                elif p.get("type") == "text" and p.get("text"):
                    out("\n" + c("1;35", "▌") + " " + c("1;35", "pi"))
                    for l in p["text"].splitlines(): out(c("35", "▌") + " " + c("1", l))
                elif p.get("type") == "toolCall":
                    calls += 1
                    line_ = f"{p.get('name')} {args_of(p.get('arguments') or {})}"
                    print("  " + c("36", "$ ") + c("36", cut(line_, width - 30)), end="", flush=True)
    elif t == "tool_execution_end":
        failed = bool(e.get("isError"))
        verdict = c("1;31", "✗ error") if failed else c("32", "✓")
        out("  " + verdict + " " + c("2", dur(int(e.get("durationMs") or 0))))
        body = text_of((e.get("result") or {}).get("content") or [])
        if body: fold(body.splitlines(), failed)
    elif t == "agent_end":
        out("\n" + c("1;33", f"■ turns {turns} · tool calls {calls} · peak context {peak} · output tokens {out_tokens}"))
    # agy writes event records: init, step_update (agent_response deltas, tool steps) and result.
    ev = e.get("event")
    if ev == "init":
        out(c("1;33", "■ agy") + "  " + c("1", (e.get("init") or {}).get("model", "?")))
    elif ev == "step_update":
        s = e.get("step_update") or {}
        kind, state = s.get("step_type"), s.get("state")
        if kind == "agent_response":
            agy_text += s.get("text_delta") or ""
            if state == "DONE" and agy_text.strip():
                out("\n" + c("1;35", "▌") + " " + c("1;35", "agy"))
                for l in agy_text.splitlines(): out(c("35", "▌") + " " + c("1", l))
            if state == "DONE": agy_text = ""
        elif kind == "tool":
            params = (s.get("tool_info") or {}).get("parameters") or {}
            line_ = f"{s.get('tool_name')} {args_of(params)}"
            if state == "ACTIVE":
                calls += 1
                print("  " + c("36", "$ ") + c("36", cut(line_, width - 30)), end="", flush=True)
            elif state == "DONE":
                out("  " + c("32", "✓") + " " + c("2", dur(int(float(s.get("duration_seconds") or 0) * 1000))))
    elif ev == "result":
        r = e.get("result") or {}; u = r.get("usage") or {}
        out("\n" + c("1;33", f"■ {r.get('status', '-')} · tool calls {calls} · input {u.get('input_tokens', 0)} (cached {u.get('cache_read_tokens', 0)}) · output {u.get('output_tokens', 0)} · {float(r.get('duration_seconds') or 0):.0f}s"))
EOF
)

case "$target" in
    *.jsonl) render=render_pi ;;
    *)       render=render_codex ;;
esac

if [ "$follow" -eq 1 ]; then
    tail -n +1 -F "$target" 2>/dev/null | "$render"
else
    "$render" < "$target"
fi
