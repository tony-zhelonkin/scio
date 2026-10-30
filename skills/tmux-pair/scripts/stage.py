#!/usr/bin/env -S python3 -I
"""Run one compute stage on a terminal of its own and render its output by weight.

Errors read red, the stage's tagged lines ("[fit] best epoch 281") read bold, plain lines read
plain, a progress bar redraws in place, and library warnings and banners read dim, once each.
The log holds the whole output as plain text, each progress bar at its final state.
Exit status is the stage's.
"""
import argparse
import codecs
import fcntl
import os
import re
import signal
import struct
import subprocess
import sys
import termios
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Z0-9]|\x1b[=>78]")
SIGNAL = re.compile(r"^(\s*\[[^\]\n]{1,40}\])(\s.*)$")
ALARM = re.compile(r"Traceback \(most recent call last\)|^\w*(Error|Exception)\b|\bError: |CUDA out of memory|^Killed|\bnan\b|^Failed|FAILED")
NOISE = re.compile("|".join([
    r"/site-packages/\S+:\d+: ",
    r"^\s*warnings\.warn\(",
    r"^(GPU|TPU|HPU|IPU) available: ",
    r"^LOCAL_RANK: ",
    r"^💡 Tip: ",
    r"^Seed set to ",
    r"^You are using a CUDA device",
    r"^Trainer will use only",
]))


def parse():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--name", required=True)
    p.add_argument("--log", required=True)
    p.add_argument("--append", action="store_true")
    p.add_argument("command", nargs=argparse.REMAINDER)
    a = p.parse_args()
    if a.command[:1] == ["--"]:
        a.command = a.command[1:]
    if not a.command:
        p.error("the stage command follows --")
    return a


class View:
    def __init__(self, log, color, width):
        self.log, self.color, self.width = log, color, width
        self.seen, self.folded = set(), 0
        self.after = None
        self.live = False

    def c(self, code, s):
        return f"\033[{code}m{s}\033[0m" if self.color else s

    def cut(self, s):
        return s if len(s) <= self.width else s[: self.width - 1] + "…"

    def out(self, s):
        sys.stdout.write(("\r\033[K" if self.live else "") + s + "\n")
        sys.stdout.flush()
        self.live = False

    def progress(self, s):
        sys.stdout.write("\r\033[K" + self.c("36", self.cut(s)))
        sys.stdout.flush()
        self.live = True

    def line(self, raw):
        segments = [s for s in raw.split("\r") if s.strip()]
        text = segments[-1].rstrip() if segments else ""
        self.log.write(text + "\n")
        self.log.flush()
        if len(segments) > 1 or self.live:
            self.after = None
            return self.out(self.c("36", self.cut(text)))
        indented = text[:1].isspace()
        if self.after == "alarm" and indented:
            return self.out(self.c("31", text))
        if self.after in ("noise", "folded") and indented:
            if self.after == "noise":
                self.out(self.c("2", self.cut(text)))
            return
        if ALARM.search(text):
            self.after = "alarm"
            return self.out(self.c("1;31", text))
        if NOISE.search(text):
            if text in self.seen:
                self.after = "folded"
                self.folded += 1
                return
            self.seen.add(text)
            self.after = "noise"
            return self.out(self.c("2", self.cut(text)))
        self.after = None
        m = SIGNAL.match(text)
        if m:
            return self.out(self.c("1;36", m.group(1)) + self.c("1", m.group(2)))
        self.out(text)


def duration(s):
    s = int(s)
    return f"{s // 3600}h{s % 3600 // 60:02d}m" if s >= 3600 else f"{s // 60}m{s % 60:02d}s" if s >= 60 else f"{s}s"


def main():
    a = parse()
    command = " ".join(a.command)
    color = not os.environ.get("NO_COLOR")
    try:
        cols, rows = os.get_terminal_size(sys.stdout.fileno())
    except OSError:
        cols, rows = 0, 0
    cols, rows = cols if cols >= 40 else 160, rows if rows >= 10 else 50
    os.makedirs(os.path.dirname(os.path.abspath(a.log)), exist_ok=True)
    log = open(a.log, "a" if a.append else "w", encoding="utf-8")
    view = View(log, color, cols)

    view.out(view.c("1;33", f"■ stage {a.name}") + "  " + view.c("1", command))
    view.out(view.c("2", f"  {os.getcwd()}  log {a.log}"))

    master, slave = os.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    signal.signal(signal.SIGINT, lambda *_: None)
    start = time.time()
    child = subprocess.Popen(["bash", "-c", command], stdout=slave, stderr=slave)
    os.close(slave)

    decode = codecs.getincrementaldecoder("utf-8")("replace")
    pending = ""
    while True:
        try:
            chunk = os.read(master, 65536)
        except OSError:
            chunk = b""
        if not chunk:
            break
        pending += ANSI.sub("", decode.decode(chunk)).replace("\r\n", "\n")
        *lines, pending = pending.split("\n")
        for raw in lines:
            view.line(raw)
        live = [s for s in pending.split("\r") if s.strip()]
        if "\r" in pending and live:
            view.progress(live[-1])
    if pending.strip():
        view.line(pending)
    status = child.wait()
    code = status if status >= 0 else 128 - status

    elapsed = duration(time.time() - start)
    folded = f" · {view.folded} repeated warning lines folded" if view.folded else ""
    log.write(f"# exit {code} after {elapsed}\n")
    log.close()
    view.out(view.c("1;32" if code == 0 else "1;31", f"■ exit {code} · {elapsed}{folded} · log {a.log}"))
    sys.exit(code)


if __name__ == "__main__":
    main()
