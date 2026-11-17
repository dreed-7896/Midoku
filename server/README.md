# Private Suwayomi server

Suwayomi and FlareSolverr behind Tailscale. Nothing listens on the public internet: no open ports,
no domain, no DNS record, so the server can't be found by scanning. Only devices signed in to your
Tailscale account can reach it, and Suwayomi still asks for a username and password.

## 1. Tailscale (once)

1. Create a free account at tailscale.com and install the Tailscale app on your iPhone.
2. Admin console → **DNS**: turn on **MagicDNS** and **HTTPS Certificates**.
3. Admin console → **Settings → Keys**: generate an auth key (reusable off, expiry 90 days is fine).

## 2. Server

Any Linux machine with Docker (VPS, home PC, Raspberry Pi):

```sh
git clone --depth 1 https://github.com/Mohammad-Rahat/Midoku-web.git /tmp/mw
mkdir -p ~/.cache/svc && cp -r /tmp/mw/server/. ~/.cache/svc/ && rm -rf /tmp/mw
cd ~/.cache/svc
cp .env.example .env
nano .env            # auth key, username, strong password, extension repo
chmod 600 .env && mkdir -p data && chmod 700 data
./retag.sh           # optional: neutral image names; add the printed lines to .env
docker compose up -d
```

The machine appears in the Tailscale admin console as `node` (or your `TS_HOSTNAME`).
The first HTTPS request takes a few seconds while the certificate is issued.

## 3. Midoku

Turn Tailscale on on the phone, then Midoku → Settings → Server:

- Address: `https://node.<your-tailnet>.ts.net` (shown in the admin console under Machines)
- Username / password: from `.env`

## Low profile on a shared VPS

- Containers are named `cache-net`, `cache-app`, `cache-helper` (change with `STACK_NAME`).
- `./retag.sh` renames the images locally, so `docker images` shows `cache-app:local` instead of Suwayomi.
- Files live in `~/.cache/svc`, with `data/` and `.env` readable only by you.
- No ports show up in `docker ps`, `ss -tlnp` or a port scan: Suwayomi listens on 127.0.0.1 inside its container.
- Other users can still see process command lines (`ps aux` shows the Java/Chrome processes) unless
  `/proc` is mounted with `hidepid=2` (needs root: `mount -o remount,hidepid=2 /proc`).
- Anyone with root, or in the `docker` group, can see and open everything. Renaming hides it from a
  casual look, not from an admin who goes looking.

## Extra privacy

- **Hide the server's IP from sites:** fill in the `SOCKS_PROXY_*` values (e.g. a VPN provider's SOCKS5).
- **Turn off Suwayomi's web interface** after setup: `WEB_UI_ENABLED=false`, then `docker compose up -d`.
- **Lock down the machine:** no ports need to be open. On a VPS, block all inbound except SSH, or
  SSH over Tailscale only (`tailscale up --ssh` on the host, then close port 22).
- The hosting provider can still read the disk. Only hardware you own avoids that.

## Updating

```sh
docker compose pull && docker compose up -d
```
