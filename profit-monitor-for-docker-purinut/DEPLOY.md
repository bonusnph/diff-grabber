# Deploy Profit Monitor (Purinut)

This folder deploys to a single VPS. The public site is `profit.sauichi.com` over HTTPS. DNS for `sauichi.com` is on Cloudflare. The `profit` record is DNS-only (not proxied), so Caddy can obtain and renew a Let's Encrypt certificate on the server.

| Item | Value |
| --- | --- |
| Public URL | https://profit.sauichi.com |
| Watch page | https://profit.sauichi.com/watch |
| Server | `139.180.214.152` |
| Path on server | `/opt/profit-monitor` |
| TLS | Let's Encrypt, issued by Caddy for `profit.sauichi.com` |

```
local source → rsync to server → docker compose build → Caddy :443 → app :3000
                                         └── Postgres (internal only)
```

Do not turn the Cloudflare proxy (orange cloud) on for `profit`. HTTP-01 renewal needs port 80 to reach this server directly. The zone SSL mode stays `full` because `https://sauichi.com` currently fails at the apex origin.

## 1. Files that matter

| File | Role |
| --- | --- |
| `Dockerfile` | Builds the SvelteKit Node server |
| `docker-compose.yml` | App + Postgres + Caddy |
| `Caddyfile` | Automatic HTTPS and reverse proxy for `profit.sauichi.com` |
| `.env` | `POSTGRES_*` and `ORIGIN` (do not commit) |

Postgres is not published to the host. The app is not published either. Only ports `80` and `443` are open.

Do not put `@`, `#`, or `/` in `POSTGRES_PASSWORD`. Compose builds `DATABASE_URL` from that value.

## 2. First-time server setup

SSH in as root, then install Docker:

```bash
ssh root@139.180.214.152
curl -fsSL https://get.docker.com | sh
```

Open the ports if a firewall is active:

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```

In Cloudflare DNS for `sauichi.com`, add an A record:

| Field | Value |
| --- | --- |
| Name | `profit` |
| IPv4 | `139.180.214.152` |
| Proxy | DNS only |

## 3. Copy the project and start it

From your machine, in `profit-monitor-for-docker-purinut`:

```bash
rsync -av --delete \
  --exclude node_modules \
  --exclude .svelte-kit \
  --exclude build \
  --exclude .git \
  --exclude .env \
  --exclude .env.local \
  --exclude .env.* \
  ./ root@139.180.214.152:/opt/profit-monitor/
```

On the server, create `/opt/profit-monitor/.env`:

```bash
POSTGRES_USER=profit
POSTGRES_PASSWORD=choose-a-strong-password
POSTGRES_DB=profit_monitor
ORIGIN=https://profit.sauichi.com
```

Then build and start. Caddy requests the certificate on startup, so the DNS record must already point at this server.

```bash
cd /opt/profit-monitor
docker compose up -d --build
docker compose ps
```

Check from the server:

```bash
curl -fsS https://profit.sauichi.com/api/health
```

You should see `{"status":"healthy", ...}`.

## 4. Update an existing deploy

```bash
rsync -av --delete \
  --exclude node_modules \
  --exclude .svelte-kit \
  --exclude build \
  --exclude .git \
  --exclude .env \
  --exclude .env.local \
  --exclude .env.* \
  ./ root@139.180.214.152:/opt/profit-monitor/

ssh root@139.180.214.152 'cd /opt/profit-monitor && docker compose up -d --build'
```

Postgres data stays in the `postgres-data` volume across rebuilds. Keep `ORIGIN=https://profit.sauichi.com` in the server `.env`.

## 5. EA webhook

In the MT4/MT5 EA, allow WebRequest for:

```
https://profit.sauichi.com
```

Webhook URL:

```
https://profit.sauichi.com/api/webhook
```

## 6. Troubleshooting

| Problem | What to check |
| --- | --- |
| Certificate is not issued | `dig +short profit.sauichi.com` must be `139.180.214.152`, and the Cloudflare proxy must be off |
| `https://profit.sauichi.com` times out | `ufw status`, `docker compose ps`, cloud/VPS firewall for 80/443 |
| Health is unhealthy | `docker compose logs profit-monitor` and `docker compose logs postgres` |
| App build fails on the server | Confirm the full source (including `Dockerfile`) is in `/opt/profit-monitor` |
| EA cannot send data | Allow `https://profit.sauichi.com` in WebRequest |

## 7. Common commands

```bash
cd /opt/profit-monitor

docker compose logs -f profit-monitor
docker compose logs -f caddy
docker compose logs -f postgres

docker compose ps
docker compose restart
docker compose down
```

To reset app data only (keeps settings volume layout):

```bash
docker compose exec postgres psql -U profit -d profit_monitor -c 'DELETE FROM accounts;'
```
