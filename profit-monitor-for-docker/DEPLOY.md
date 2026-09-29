# Deploy Profit Monitor

This folder deploys to one VPS. The public site is `https://profit.sumofx.co`. DNS for `sumofx.co` is on Cloudflare. The `profit` A record is proxied. A page rule for `*profit.sumofx.co/*` sets SSL to Full (strict) and turns Browser Integrity Check off for that hostname only. Caddy still terminates Let's Encrypt on the server.

The previous Docker Hub + Cloudflare Tunnel flow is kept in [`DEPLOY-TUNNEL.md`](./DEPLOY-TUNNEL.md) and `docker-compose.tunnel.yml`. Use that only when this server cannot accept traffic on port 443.

| Item | Value |
| --- | --- |
| Public URL | https://profit.sumofx.co |
| Watch page | https://profit.sumofx.co/watch |
| Server | `68.183.185.48` |
| Path on server | `/home/profit-monitor` |
| TLS | Let's Encrypt via TLS-ALPN on port 443 |

```
local source → rsync to server → docker compose build → Caddy :443 → app :3000
                                         └── Postgres (internal only)
```

Caddy listens on ports 80 and 443. `http://profit.sumofx.co` redirects to `https://profit.sumofx.co`. Other names on port 80 are forwarded to the WordPress container, which must not publish host port 80 itself. Keep the Cloudflare proxy on for `profit`. Do not change zone SSL away from Flexible, and do not change the `sumofx.co` or `www` records. The page rule is what makes Cloudflare connect to origin port 443 with the real certificate. Browser Integrity Check stays off on that rule so MT4/MT5 WebRequest is not challenged.

The certificate is valid until 2026-12-28. Let's Encrypt renewal cannot complete while the proxy is on, because the TLS-ALPN challenge would hit Cloudflare instead of Caddy. To renew, set the `profit` record to DNS-only, restart Caddy, wait until the certificate renews, then turn the proxy back on. Leave the page rule in place.

## 1. Files that matter

| File | Role |
| --- | --- |
| `Dockerfile` | Builds the SvelteKit Node server |
| `docker-compose.yml` | App + Postgres + Caddy |
| `Caddyfile` | HTTPS reverse proxy for `profit.sumofx.co` |
| `.env` | `POSTGRES_*` and `ORIGIN` (do not commit) |
| `docker-compose.tunnel.yml` | Fallback tunnel stack |
| `settings-seed.json`, `accounts-seed.json` | Live on the server only. Imported once, then ignored |

Postgres is not published. The app is not published. Only port `443` is published for this stack.

Do not put `@`, `#`, or `/` in `POSTGRES_PASSWORD`. Compose builds `DATABASE_URL` from that value.

## 2. DNS

In Cloudflare DNS for `sumofx.co`:

| Field | Value |
| --- | --- |
| Name | `profit` |
| Type | A |
| IPv4 | `68.183.185.48` |
| Proxy | DNS only |

Remove the tunnel CNAME for `profit` before creating this record. The tunnel ingress is documented in `DEPLOY-TUNNEL.md`.

## 3. Copy the project and start it

From `profit-monitor-for-docker` on your machine. Do not use `--delete`: the seed JSON files exist only on the server.

```bash
rsync -av \
  --exclude node_modules \
  --exclude .svelte-kit \
  --exclude build \
  --exclude .git \
  --exclude .env \
  --exclude .env.local \
  --exclude .env.* \
  ./ root@68.183.185.48:/home/profit-monitor/
```

On the server, `/home/profit-monitor/.env` must include:

```bash
POSTGRES_USER=profit
POSTGRES_PASSWORD=choose-a-long-password
POSTGRES_DB=profit_monitor
ORIGIN=https://profit.sumofx.co
```

The DNS record must already point at this server before Caddy can finish the certificate.

```bash
cd /home/profit-monitor
docker compose up -d --build
docker compose ps
```

Check:

```bash
curl -fsS https://profit.sumofx.co/api/health
```

You should see `{"status":"healthy", ...}`.

## 4. Update an existing deploy

```bash
rsync -av \
  --exclude node_modules \
  --exclude .svelte-kit \
  --exclude build \
  --exclude .git \
  --exclude .env \
  --exclude .env.local \
  --exclude .env.* \
  ./ root@68.183.185.48:/home/profit-monitor/

ssh root@68.183.185.48 'cd /home/profit-monitor && docker compose up -d --build'
```

Postgres data stays in the `postgres-data` volume. Keep `ORIGIN=https://profit.sumofx.co` in the server `.env`.

## 5. EA webhook

Allow WebRequest for:

```
https://profit.sumofx.co
```

Webhook URL:

```
https://profit.sumofx.co/api/webhook
```

## 6. Fallback to the tunnel

Stop this stack without deleting the database volume, then start the tunnel file:

```bash
cd /home/profit-monitor
docker compose down
docker compose -f docker-compose.tunnel.yml up -d
```

Restore the Cloudflare tunnel hostname `profit.sumofx.co` → `http://profit-monitor:3000` as described in `DEPLOY-TUNNEL.md`. `CLOUDFLARE_TUNNEL_TOKEN` stays in `.env` for that path.

## 7. Troubleshooting

| Problem | What to check |
| --- | --- |
| Certificate is not issued | Renewal needs the `profit` record DNS-only for the TLS-ALPN challenge, then the proxy turned back on. `docker compose logs caddy` |
| Caddy cannot bind port 80 | WordPress is still publishing host port 80. Remove that publish so Caddy can take it |
| Health is unhealthy | `docker compose logs profit-monitor` and `docker compose logs postgres` |
| EA cannot send data | Allow `https://profit.sumofx.co` in WebRequest |

## 8. Common commands

```bash
cd /home/profit-monitor

docker compose logs -f profit-monitor
docker compose logs -f caddy
docker compose logs -f postgres

docker compose ps
docker compose restart
docker compose down
```
