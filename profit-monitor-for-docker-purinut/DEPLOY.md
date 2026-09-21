# Deploy Profit Monitor (Purinut)

This folder deploys to a single VPS and is reached by IP over HTTPS. There is no domain and no Cloudflare tunnel.

| Item | Value |
| --- | --- |
| Public URL | https://139.180.214.152 |
| Watch page | https://139.180.214.152/watch |
| Server | `139.180.214.152` |
| Path on server | `/opt/profit-monitor` |
| TLS | Self-signed certificate with an IP SAN (public CAs do not issue certs for a raw IP) |

```
local source → rsync to server → docker compose build → Caddy :443 → app :3000
                                         └── Postgres (internal only)
```

Browsers will warn that the certificate is untrusted. That is expected for HTTPS on a raw IP. Accept the warning once to continue.

## 1. Files that matter

| File | Role |
| --- | --- |
| `Dockerfile` | Builds the SvelteKit Node server |
| `docker-compose.yml` | App + Postgres + Caddy |
| `Caddyfile` | HTTP → HTTPS redirect and reverse proxy |
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
ORIGIN=https://139.180.214.152
```

Create a self-signed cert for the server IP:

```bash
mkdir -p /opt/profit-monitor/certs
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /opt/profit-monitor/certs/key.pem \
  -out /opt/profit-monitor/certs/cert.pem \
  -subj "/CN=139.180.214.152" \
  -addext "subjectAltName=IP:139.180.214.152,IP:127.0.0.1"
chmod 600 /opt/profit-monitor/certs/key.pem
```

Then build and start:

```bash
cd /opt/profit-monitor
docker compose up -d --build
docker compose ps
```

Check from the server:

```bash
curl -k https://127.0.0.1/api/health
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

Postgres data stays in the `postgres-data` volume across rebuilds.

## 5. EA webhook

In the MT4/MT5 EA, allow WebRequest for:

```
https://139.180.214.152
```

Webhook URL:

```
https://139.180.214.152/api/webhook
```

MetaTrader may reject the self-signed certificate. If the EA cannot POST, install the Caddy local CA on that Windows machine or temporarily test with a trusted cert.

## 6. Troubleshooting

| Problem | What to check |
| --- | --- |
| Browser certificate warning | Expected. Click through once. |
| `https://139.180.214.152` times out | `ufw status`, `docker compose ps`, cloud/VPS firewall for 80/443 |
| Health is unhealthy | `docker compose logs profit-monitor` and `docker compose logs postgres` |
| App build fails on the server | Confirm the full source (including `Dockerfile`) is in `/opt/profit-monitor` |
| EA cannot send data | Allow the IP in WebRequest and confirm the self-signed cert is accepted |

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
