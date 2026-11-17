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
git clone https://github.com/Mohammad-Rahat/Midoku-web.git
cd Midoku-web/server
cp .env.example .env
nano .env            # auth key, username, strong password, extension repo
docker compose up -d
```

The machine appears in the Tailscale admin console as `reader` (or your `TS_HOSTNAME`).
The first HTTPS request takes a few seconds while the certificate is issued.

## 3. Midoku

Turn Tailscale on on the phone, then Midoku → Settings → Server:

- Address: `https://reader.<your-tailnet>.ts.net` (shown in the admin console under Machines)
- Username / password: from `.env`

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
