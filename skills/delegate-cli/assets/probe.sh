#!/usr/bin/env bash

set -eu

usage() {
    echo "usage: probe.sh --workdir DIR [--model MODEL] [--sandbox MODE] [--web] [--file-read-check]" >&2
}

fail() {
    code="$1"
    shift
    printf 'probe.sh: %s\n' "$*" >&2
    exit "$code"
}

workdir=
model=
sandbox=
want_web=0
file_read_check=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workdir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            workdir="$2"
            shift 2
            ;;
        --model)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            model="$2"
            shift 2
            ;;
        --sandbox)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            sandbox="$2"
            shift 2
            ;;
        --web)
            want_web=1
            shift
            ;;
        --file-read-check)
            file_read_check=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[ -n "$workdir" ] || { usage; exit 2; }
[ -d "$workdir" ] || fail 2 "workdir is not a directory: $workdir"

command -v codex >/dev/null 2>&1 || fail 10 "codex is not available on PATH"

set +e
codex_version=$(codex --version 2>/dev/null)
version_status=$?
codex_help=$(codex exec --help 2>&1)
help_status=$?
set -e

[ "$version_status" -eq 0 ] && [ -n "$codex_version" ] \
    || fail 11 "codex --version failed"
[ "$help_status" -eq 0 ] && [ -n "$codex_help" ] \
    || fail 11 "codex exec --help failed"

has_output_last_message=0
has_stdin_prompt=0
has_config=0
has_enable=0
has_bypass=0
has_search_flag=0
has_workdir=0
has_skip_git_check=0
has_model=0
has_sandbox=0

printf '%s\n' "$codex_help" | grep -Eq -- '--output-last-message([=[:space:]<,]|$)' \
    && has_output_last_message=1
printf '%s\n' "$codex_help" | grep -Eiq -- 'stdin' \
    && has_stdin_prompt=1
printf '%s\n' "$codex_help" | grep -Eq -- '(^|[[:space:],])-c([[:space:],<]|$)|--config([=[:space:]<,]|$)' \
    && has_config=1
printf '%s\n' "$codex_help" | grep -Eq -- '--enable([=[:space:]<,]|$)' \
    && has_enable=1
printf '%s\n' "$codex_help" | grep -Eq -- '--dangerously-bypass-approvals-and-sandbox([[:space:],]|$)' \
    && has_bypass=1
printf '%s\n' "$codex_help" | grep -Eq -- '(^|[[:space:],])--search([=[:space:]<,]|$)' \
    && has_search_flag=1
printf '%s\n' "$codex_help" | grep -Eq -- '(^|[[:space:],])-C([[:space:],<]|$)|--cd([=[:space:]<,]|$)' \
    && has_workdir=1
printf '%s\n' "$codex_help" | grep -Eq -- '--skip-git-repo-check([[:space:],]|$)' \
    && has_skip_git_check=1
printf '%s\n' "$codex_help" | grep -Eq -- '(^|[[:space:],])-m([[:space:],<]|$)|--model([=[:space:]<,]|$)' \
    && has_model=1
printf '%s\n' "$codex_help" | grep -Eq -- '(^|[[:space:],])-s([[:space:],<]|$)|--sandbox([=[:space:]<,]|$)' \
    && has_sandbox=1

web_mode=unsupported
if [ "$has_config" -eq 1 ] && [ "$has_enable" -eq 1 ]; then
    web_mode=config_enable
fi

# The flag checks below prove -m EXISTS, never that a value is ACCEPTED: a model
# this CLI is too old for is rejected by the server after launch, tens of seconds
# in, with exit 1. CODEX_VERSION above is the fact that decides it — the server
# refuses a model newer than the installed codex by name. Report the config's
# model too, so a caller can see what the machine would pick unasked.
codex_home="${CODEX_HOME:-$HOME/.codex}"
configured_model=
if [ -r "$codex_home/config.toml" ]; then
    configured_model=$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$codex_home/config.toml" | head -n 1)
fi

printf 'CODEX_VERSION=%q\n' "$codex_version"
printf 'CODEX_MODEL_CONFIGURED=%s\n' "${configured_model:--}"
if [ -n "$model" ]; then
    printf 'CODEX_MODEL_REQUESTED=%s\n' "$model"
    printf 'CODEX_MODEL_REQUESTED_VALIDATED=0\n'
fi
printf 'HAS_OUTPUT_LAST_MESSAGE=%s\n' "$has_output_last_message"
printf 'HAS_STDIN_PROMPT=%s\n' "$has_stdin_prompt"
printf 'HAS_CONFIG=%s\n' "$has_config"
printf 'HAS_ENABLE=%s\n' "$has_enable"
printf 'HAS_BYPASS=%s\n' "$has_bypass"
printf 'HAS_SEARCH_FLAG=%s\n' "$has_search_flag"
printf 'WEB_MODE=%s\n' "$web_mode"

[ "$has_output_last_message" -eq 1 ] \
    || fail 12 "codex exec lacks --output-last-message"
[ "$has_stdin_prompt" -eq 1 ] \
    || fail 12 "codex exec help does not document stdin prompts"
[ "$has_workdir" -eq 1 ] \
    || fail 12 "codex exec lacks -C/--cd"
[ "$has_skip_git_check" -eq 1 ] \
    || fail 12 "codex exec lacks --skip-git-repo-check"
if [ -n "$model" ] && [ "$has_model" -ne 1 ]; then
    fail 12 "codex exec lacks -m/--model"
fi
if [ -n "$sandbox" ] && [ "$has_sandbox" -ne 1 ]; then
    fail 12 "codex exec lacks -s/--sandbox"
fi
if [ "$want_web" -eq 1 ] && [ "$web_mode" != config_enable ]; then
    fail 13 "web search is unsupported by this codex exec"
fi

if [ "$file_read_check" -eq 1 ]; then
    check_dir=$(mktemp -d "${TMPDIR:-/tmp}/scio-delegate-probe.XXXXXX") \
        || fail 14 "could not create the file-read check directory"
    trap 'rm -rf "$check_dir"' EXIT

    nonce="SCIO_DELEGATE_FILE_READ_${$}_$(date +%s)"
    nonce_file="$check_dir/nonce.txt"
    prompt_file="$check_dir/prompt.md"
    final_file="$check_dir/final.md"
    stream_file="$check_dir/stream.log"
    printf '%s\n' "$nonce" > "$nonce_file"
    printf 'Read %s with a file tool and reply with only its exact contents.\n' "$nonce_file" \
        > "$prompt_file"

    codex_args=(exec -C "$workdir" --skip-git-repo-check -o "$final_file")
    [ -z "$model" ] || codex_args+=(-m "$model")
    [ -z "$sandbox" ] || codex_args+=(-s "$sandbox")

    if codex "${codex_args[@]}" - < "$prompt_file" > "$stream_file" 2>&1; then
        check_status=0
    else
        check_status=$?
    fi
    # The denial is a fact in the stream, and it is checked FIRST because codex
    # does not report it in its exit code. Measured in a v0.5.10 container on
    # 2026-08-25: bwrap fails to create a namespace, every file tool fails, and
    # codex still exits 0. A caller trusting the exit status gets a confident
    # answer written without ever seeing the repo, which is how three pilot
    # scripts were authored blind.
    if LC_ALL=C grep -Eqi 'bwrap|landlock|seccomp|unshare|new namespace|sandbox helper|Operation not permitted' \
            "$stream_file" 2>/dev/null; then
        printf 'SANDBOX_FILE_READ=blocked\n'
        printf 'probe.sh: codex could not read a file with sandbox %s, and exited %s anyway.\n' \
            "${sandbox:-default}" "$check_status" >&2
        printf 'probe.sh: it will answer from the prompt alone, so any path it names is a guess.\n' >&2
        printf 'probe.sh: relaunch with --sandbox danger-full-access, which is what removes the\n' >&2
        printf 'probe.sh: bwrap call, or relax the container policy (scbio-docker\n' >&2
        printf 'probe.sh: docs/ai-integration.md). --bypass also works and is wider than needed.\n' >&2
        exit 14
    fi

    if [ "$check_status" -ne 0 ]; then
        fail 14 "codex could not inspect the nonce file (exit $check_status)"
    fi

    # Exit 0 and no nonce: it answered without proving it read anything. Distinct
    # from `blocked` because the cause is unidentified, and reported rather than
    # guessed at.
    if ! grep -Fq -- "$nonce" "$final_file" 2>/dev/null; then
        printf 'SANDBOX_FILE_READ=unverified\n'
        fail 14 "codex exited 0 but its output did not contain the nonce — it did not demonstrably read the file"
    fi
    printf 'SANDBOX_FILE_READ=ok\n'
fi
