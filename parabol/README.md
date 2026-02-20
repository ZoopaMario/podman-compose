# Parabol on Podman + nginx (TLS) — build / restore / update notes

This README documents the working deployment that resulted from debugging multiple issues:
- blank UI (JS/CSS loading from `localhost:3000` / `0.0.0.0`)
- `preDeploy` failing due to `CDN_BASE_URL` rules
- Podman/nginx DNS quirks (nginx couldn’t resolve Podman container names)
- reverse-proxy + websocket requirements
- `podman-compose` network pitfalls and healthcheck mistakes

It is written so you can **recreate** the stack from scratch, **back it up**, and **upgrade** later.

---

## Architecture (final working state)

- **Parabol** runs as a container (uWebSockets-based Node server) on **HTTP** (inside container).
- **nginx** terminates **HTTPS** for `https://<your-parabol-domain>` and proxies to Parabol over HTTP.
- **Postgres** uses `pgvector/pgvector:0.8.0-pg16` with a persistent host volume.
- **Valkey** (Redis compatible) runs in-memory (tmpfs).
- Optional: **tgi-proxy** (FastAPI) to bridge Parabol’s AI generation calls to a LiteLLM/OpenAI-compatible endpoint.

### Why TLS is terminated at nginx (and Parabol stays HTTP)
Parabol’s built-in server expects normal HTTP and websockets; setting `PROTO=https` / serving HTTPS directly from Parabol caused protocol confusion (“HTTP Version Not Supported”, etc.). The reliable pattern is:

- **Parabol:** `PROTO=http`, `PORT=3000` (container)
- **nginx:** handles `https://<your-parabol-domain>` externally and sets `X-Forwarded-Proto: https`

---

## Versions observed in this setup

- Podman: `4.3.1`
- podman-compose: `1.0.3`
- Parabol image: `parabol:v12.3.0` (and `localhost/parabol:v12.3.0-sharp` variant used)
- Postgres: `pgvector/pgvector:0.8.0-pg16` (Postgres 16)
- Valkey: `valkey/valkey:9.0-alpine`
- nginx: `nginx/1.29.x` (as observed in headers/logs)

---

## File / directory layout

**Config inputs**
- `/mnt/data/parabol/config/parabol.env`  
- `/mnt/data/parabol/config/tgi_litellm_proxy.py` (optional)
- `/mnt/data/nginx/conf.d/65-parabol.conf`

**Persistent data**
- `/srv/parabol/postgres/pgdata` → mounted into Postgres container at `/var/lib/postgresql/data`

---

## Key quirks & workarounds (what bit us)

### 1) `CDN_BASE_URL` MUST be blank with local file store
Parabol’s `preDeploy` hard-fails if:
- `FILE_STORE_PROVIDER=local` **and** `CDN_BASE_URL` is non-empty.

The exact failure was:
> `Error: Env Var CDN_BASE_URL must be blank when FILE_STORE_PROVIDER=local`

✅ Working configuration:
- `FILE_STORE_PROVIDER=local`
- `CDN_BASE_URL=` (empty)
- `PROXY_CDN=false`

### 2) “Blank page” symptom usually = wrong asset/publicPath
When Parabol emits HTML that references JS/CSS from:
- `http://localhost:3000/static/...`
- `http://0.0.0.0/static/...`

…browsers won’t load those assets from your domain, and you get a blank app shell.

Root causes we hit:
- container `HOST/PORT/PROTO` being set to values meant for the *outside world*
- confusion between “bind address” vs “public origin”
- reverse proxy headers not being trusted

✅ Fix pattern:
- Keep container bind as `HOST=0.0.0.0`, `PORT=3000`, `PROTO=http`
- Set `APP_ORIGIN=https://<your-parabol-domain>`
- Ensure nginx sets `X-Forwarded-Proto`, and (optionally) set `TRUSTED_PROXY_COUNT=1` in Parabol

> If you see stale asset URLs even after fixing config, unregister the service worker / hard refresh.

### 3) Nginx-in-container: `proxy_pass http://127.0.0.1:13500` is NOT the host loopback
Inside the nginx container, `127.0.0.1` is the nginx container itself. That yielded:
- `connect() failed (111: Connection refused)` → 502

### 4) Podman DNS + nginx name-resolution: container names may not resolve
Attempting to proxy to an upstream like `http://web:3000` failed with:
- `host not found in upstream "web"` (nginx config test failure)
- or runtime DNS timeouts (`could not be resolved (110: Operation timed out)`)

Podman provides a special DNS zone (commonly `*.dns.podman`) and search domains,
but nginx’s resolver behavior often doesn’t match “glibc-style search suffixes”.

### 5) **Final working approach: Workaround B**
**Publish Parabol on a host-reachable interface and proxy via `host.containers.internal`.**

This avoids all of:
- nginx → Podman DNS issues
- nginx needing to be on the same podman network
- dealing with `dns.podman` resolver configs

### 6) podman-compose network pitfalls
We encountered:
- `KeyError: 'parabol'` when the compose file referenced a network not present as expected.

Mitigations:
- define the network explicitly in `docker-compose.yml`
- create it manually if required (`podman network create parabol`)
- or avoid custom networks and rely on default compose network behavior (less predictable with podman-compose)

### 7) Postgres “role root does not exist” spam
This came from a **broken healthcheck** running `pg_isready` without the right user/db.
Fix by explicitly passing:
- `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB`

### 8) Valkey memory overcommit warning
Valkey warned about `vm.overcommit_memory`. It’s usually safe for light usage but recommended:
```bash
sudo sysctl -w vm.overcommit_memory=1
# persist in /etc/sysctl.conf if desired
```

---

## Working `parabol.env` (template)

Create `/mnt/data/parabol/config/parabol.env`:

```dotenv
# --- SERVER CONFIG (INTERNAL BIND) ---
HOST=0.0.0.0
PORT=3000
PROTO=http

# Public origin clients use
APP_ORIGIN=https://agile.zoopa.dev

# Recommended when running behind exactly one reverse proxy (nginx)
TRUSTED_PROXY_COUNT=1

SERVER_SECRET=REPLACE_ME

# --- CDN / FILE ---
FILE_STORE_PROVIDER=local
PROXY_CDN=false
CDN_BASE_URL=

# --- DATABASE ---
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=pgparaboladmin
POSTGRES_PASSWORD=REPLACE_ME
POSTGRES_DB=parabol-saas
POSTGRES_USE_PGVECTOR=true

# --- REDIS / VALKEY ---
REDIS_URL=redis://valkey:6379
REDIS_PASSWORD=

# --- MAIL ---
MAIL_PROVIDER=debug

# --- LOGGING ---
AUDIT_LOGS=true

# --- AI ---
# To disable embedding workers while you stabilize the deployment:
AI_EMBEDDER_WORKERS=0

# Note: when you inspected embedder.js, the only obvious modelId present was:
#   parabol-provided
# If you re-enable AI routing, prefer using that modelId unless you verify others.
#
# AI_GENERATION_MODELS=[{"model":"text-generation-inference:parabol-provided","url":"http://tgi-proxy:8080","maxTokens":4096}]
# AI_EMBEDDING_MODELS=[{"model":"text-embeddings-inference:...","url":"http://...","maxTokens":4096}]
```

---

## Working `docker-compose.yml` (Podman + Workaround B)

This runs Parabol on internal port 3000 and publishes it to the **host** on 13500.
Nginx then proxies to `host.containers.internal:13500`.

```yaml
version: "3.8"

services:
  postgres:
    image: pgvector/pgvector:0.8.0-pg16
    container_name: parabol-postgres
    env_file:
      - /mnt/data/parabol/config/parabol.env
    volumes:
      - /srv/parabol/postgres/pgdata:/var/lib/postgresql/data:Z
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 20
    restart: unless-stopped

  valkey:
    image: valkey/valkey:9.0-alpine
    container_name: parabol-valkey
    tmpfs:
      - /data
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli ping | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 20
    restart: unless-stopped

  # Optional: TGI proxy that points to LiteLLM/OpenAI-compatible endpoint
  tgi-proxy:
    image: python:3.12-slim
    container_name: parabol-tgi-proxy
    environment:
      - LITELLM_BASE_URL=http://host.containers.internal:4000/v1
      - LITELLM_API_KEY=sk-REPLACE_ME
      - LITELLM_MODEL=qwen3:4b-instruct-REPLACE_ME
    volumes:
      - /mnt/data/parabol/config/tgi_litellm_proxy.py:/app/tgi_litellm_proxy.py:ro
    working_dir: /app
    command:
      - bash
      - -lc
      - |
        pip install --no-cache-dir fastapi uvicorn httpx &&
        uvicorn tgi_litellm_proxy:app --host 0.0.0.0 --port 8080
    ports:
      - "3050:8080"
    restart: unless-stopped

  web:
    image: localhost/parabol:v12.3.0-sharp
    container_name: parabol-web
    env_file:
      - /mnt/data/parabol/config/parabol.env
    working_dir: /home/node/parabol
    command: ["bash", "-lc", "node dist/preDeploy.js && node dist/web.js"]
    # Workaround B: publish Parabol to host and proxy via host.containers.internal
    ports:
      - "0.0.0.0:13500:3000"
      # If you want to restrict to localhost only:
      # - "127.0.0.1:13500:3000"
    restart: unless-stopped
    depends_on:
      - postgres
      - valkey
```

> Note: If you restrict to `127.0.0.1:13500`, nginx must be able to reach host loopback.
> If nginx runs in a container, prefer publishing on a host interface nginx can reach,
> or run nginx with `--network=host`.

---

## nginx config (Workaround B)

Place at `/mnt/data/nginx/conf.d/65-parabol.conf`:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name your.parabol.host;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name your.parabol.host;

    ssl_certificate     /path/to/your/tls/fullchain.pem;
    ssl_certificate_key /path/to/your/tls/privkey.pem;

    ssl_session_timeout 1d;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    location / {
        # Workaround B: Parabol published on the host
        proxy_pass http://host.containers.internal:13500;

        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  $server_port;

        # websockets (Parabol needs this)
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
```

Reload nginx (containerized):
```bash
podman exec nginx nginx -t && podman exec nginx nginx -s reload
```

---

## Bring-up / rebuild procedure

### 1) Create directories (once)
```bash
sudo mkdir -p /mnt/data/parabol/config
sudo mkdir -p /srv/parabol/postgres/pgdata
sudo mkdir -p /mnt/data/nginx
