#!/usr/bin/env python3
"""Throttled KEGG REST client: every call in every process stays under 3 requests per second.

Contract:
  * One shared timestamp file serialises all processes on this machine, so parallel
    agents cannot jointly exceed the limit (default spacing 0.4 s, i.e. 2.5 calls/s).
  * `get`, `conv` and `link` split long entry lists into batches of 10 joined by `+`.
  * HTTP 403 means KEGG has blocked this address: the client stops at once and never retries.
  * 400 and 404 fail with a message; 5xx and timeouts retry twice, each retry throttled.
  * Output is KEGG's tab-separated text, or JSON pairs with `--json`.
"""

import argparse
import fcntl
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://rest.kegg.jp"
MIN_GAP = float(os.environ.get("KEGG_MIN_GAP", "0.4"))
STAMP = os.path.join(tempfile.gettempdir(), "kegg_rest.stamp")
BATCH = 10
GET_OPTIONS = ("aaseq", "ntseq", "mol", "kcf", "image", "kgml", "json")
SINGLE_ENTRY_OPTIONS = ("image", "kgml", "json")


class KeggBlocked(RuntimeError):
    """KEGG returned 403: the address is blocked and further calls make it worse."""


def wait_for_slot():
    """Sleep until MIN_GAP has passed since the last KEGG call by any process, then claim the slot."""
    with open(STAMP, "a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        text = fh.read().strip()
        last = float(text) if text else 0.0
        delay = last + MIN_GAP - time.time()
        if delay > 0:
            time.sleep(delay)
        fh.seek(0)
        fh.truncate()
        fh.write(repr(time.time()))
        fh.flush()


def request(path, binary=False):
    """GET one KEGG path through the throttle and return text, or bytes when binary."""
    url = f"{BASE}/{path}"
    for attempt in range(3):
        wait_for_slot()
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                body = resp.read()
                return body if binary else body.decode("utf-8")
        except urllib.error.HTTPError as err:
            if err.code == 403:
                raise KeggBlocked(f"HTTP 403 from {url}: KEGG blocked this address; stop and wait") from err
            if err.code in (400, 404):
                raise SystemExit(f"HTTP {err.code} for {url}: check the entry, database and option spelling")
            if attempt == 2:
                raise SystemExit(f"HTTP {err.code} for {url} after 3 attempts")
        except (urllib.error.URLError, TimeoutError) as err:
            if attempt == 2:
                raise SystemExit(f"{url} unreachable after 3 attempts: {err}")
    raise SystemExit(f"{url} failed")


def expand(items):
    """Read entries from the command line, with `@file` expanding to one entry per line."""
    out = []
    for item in items:
        if item.startswith("@"):
            with open(item[1:]) as fh:
                out.extend(line.strip() for line in fh if line.strip())
        else:
            out.append(item)
    return out


def batched(entries):
    for start in range(0, len(entries), BATCH):
        yield "+".join(entries[start:start + BATCH])


def run(args):
    op = args.op
    rest = args.args
    if op == "info":
        return request(f"info/{rest[0]}")
    if op == "list":
        return request("list/" + "/".join(rest))
    if op == "find":
        database, query = rest[0], urllib.parse.quote(rest[1], safe="")
        suffix = f"/{rest[2]}" if len(rest) > 2 else ""
        return request(f"find/{database}/{query}{suffix}")
    if op == "get":
        option = args.option
        entries = expand(rest)
        if option in SINGLE_ENTRY_OPTIONS and len(entries) != 1:
            raise SystemExit(f"--option {option} accepts exactly one entry")
        suffix = f"/{option}" if option else ""
        binary = option == "image"
        chunks = [request(f"get/{group}{suffix}", binary=binary) for group in batched(entries)]
        return chunks[0] if binary else "".join(chunks)
    if op in ("conv", "link"):
        target, sources = rest[0], expand(rest[1:])
        whole_database = len(sources) == 1 and ":" not in sources[0]
        if whole_database:
            return request(f"{op}/{target}/{sources[0]}")
        return "".join(request(f"{op}/{target}/{group}") for group in batched(sources))
    if op == "ddi":
        return "".join(request(f"ddi/{group}") for group in batched(expand(rest)))
    raise SystemExit(f"unknown operation {op}")


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("op", choices=["info", "list", "find", "get", "conv", "link", "ddi"])
    parser.add_argument("args", nargs="+", help="operation arguments, see references/kegg-rest.md")
    parser.add_argument("--option", choices=GET_OPTIONS, help="`get` output format")
    parser.add_argument("--json", action="store_true", help="emit tab-separated rows as a JSON list of lists")
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    return parser


def main():
    args = build_parser().parse_args()
    result = run(args)
    if args.json and isinstance(result, str):
        result = json.dumps([line.split("\t") for line in result.splitlines() if line])
    if args.output:
        with open(args.output, "wb" if isinstance(result, bytes) else "w") as fh:
            fh.write(result)
    elif isinstance(result, bytes):
        raise SystemExit("binary output needs -o FILE")
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    try:
        main()
    except KeggBlocked as err:
        sys.exit(str(err))
