---
name: container-port-tunnel
description: >-
  Expose a browser tool (marimo, httpgd, dashboard) running inside the
  devcontainer to the user's laptop, with a URL that survives restarts. Use
  whenever the user needs a URL for a server started in this container, or
  reports that a served URL fails.
license: MIT
---

# Container port tunnel

## Topology

A project's sessions share one devcontainer, and every server they start listens
inside it. The compose template ships its `ports:` block commented out, so the
container publishes nothing and its bridge IP is reachable only from the lab
host: laptop -> ssh -> lab host -> container IP -> port.

Get the IP with `hostname -I`; it changes on every rebuild. `ss`, `netstat` and
`lsof` are all absent from the image, so probe ports directly:

```bash
python3 -c "import socket; [print(p, socket.socket().connect_ex(('127.0.0.1',p))==0) for p in (2716,2719,2782)]"
```

## Pin the token

Keep tokens **on**. These are edit servers, and an unauthenticated port is code
execution for anyone who can reach the docker bridge.

Pin the token to a file rather than accepting the random one marimo prints. A
banner token rotates on every launch and does not flush reliably into a
redirected log, so a bookmarked URL dies at the next restart. A pinned token
means the same URL works for as long as the port keeps its assignment.

```bash
# once per port
mkdir -p ~/.config/marimo-tokens
head -c 16 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=' > ~/.config/marimo-tokens/<PORT>
chmod 600 ~/.config/marimo-tokens/<PORT>
```

The token files live under `~/.config/`, outside every repository, so no token
is ever a candidate for a commit.

## Serve

```bash
marimo edit --headless --host 0.0.0.0 --port <PORT> \
  --token-password-file ~/.config/marimo-tokens/<PORT> <notebook.py> > <log> 2>&1 &
```

**Verify before handing over a URL.** With the token it returns 200; with a wrong
one it redirects to `/auth/login`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -L \
  "http://127.0.0.1:<PORT>/?access_token=$(cat ~/.config/marimo-tokens/<PORT>)"
```

## Hand the user exactly two lines

```
ssh -L <PORT>:<CONTAINER_IP>:<PORT> <user>@<lab-host>
http://localhost:<PORT>/?access_token=<contents of the port's token file>
```

Target the **container IP**: a `-L PORT:localhost:PORT` tunnel lands on the host
loopback, which has no listeners for these servers. Tunnel several ports in one
command by repeating `-L`.

For permanent localhost tunnels instead, publish `127.0.0.1:<range>:<range>`
under `ports:` in `.devcontainer/docker-compose.yml`; it applies at the next
rebuild.
