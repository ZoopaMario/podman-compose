# openQA on Podman Compose (Rootless / ARM64)

This repo runs a stable openQA instance on **aarch64** using:
* `postgres` (DB)
* `openqa-webui` (Apache + WebUI)
* `openqa-worker` (QEMU worker)
* `openqa-websockets` (Separate WebSocket daemon)

---

## 1. Storage & Prerequisites

**Critical:** Do **not** use NFS for configuration files (`/config`). The containers require stable inodes on a local filesystem to avoid "Stale file handle" errors during restarts or edits.

### Directory Layout (Repository: `openqa/prod`)
```bash
mkdir -p \
  openqa/prod/postgres \
  openqa/prod/db \
  openqa/prod/pool \
  openqa/prod/images \
  openqa/prod/testresults \
  openqa/prod/share/factory \
  openqa/prod/share/tests \
  openqa/prod/config/apache2/vhosts.d \
  openqa/prod/config/etc-openqa \
  openqa/prod/config/worker

```

### Networking

Create the external proxy network used by Nginx/Apache:

```bash
podman network create openqa-proxy || true

```

### Permissions

Containers run as user `geekotest` inside a rootless user namespace.

```bash
# geekotest (UID 495, GID 65533) -> host 100494:165532
# worker pool user (UID 496, GID 65533) -> host 100495:165532
cd openqa/prod
podman unshare chown -R 495:65533 config db share testresults images
podman unshare chown -R 496:65533 pool

# Required directory/file modes
podman unshare find db share pool -type d -exec chmod 2775 {} +
podman unshare find config -type d -exec chmod 775 {} +
podman unshare find config db share pool -type f -exec chmod 664 {} +
podman unshare chmod -R 777 images testresults

```

---

## 2. Configuration Files

Tracked examples live in `openqa/prod/config.example/`. Runtime files live in `openqa/prod/config/` and are gitignored on purpose.

Initialize the runtime folder once:

```bash
cd openqa/prod
cp -a config.example config
```

After that, edit values directly in `openqa/prod/config/...`; `docker-compose.yml` mounts `./config/etc-openqa` and `./config/worker/*` directly, so no extra copy/move step is needed during normal operation.

### A) Database Connection (`etc-openqa/database.ini`)

**Important:** Use `host=postgres` to match the container service name.

```ini
[production]
dsn = dbi:Pg:dbname=openqa;host=postgres;port=5432
user = openqa_prod
password = change_me

```

### B) General Config (`etc-openqa/openqa.ini`)

```ini
[global]
branding = plain
# Optional: Lock down new registrations
disable_registration = 1

```

### C) Worker Config (`worker/workers.ini`)

**Important:** Define the architecture (ARM64) to prevent the worker from crashing on x86 checks.

```ini
[global]
WORKER_CLASS = qemu_aarch64,tap
# WORKER_CLASS = qemu_x86_64,tap  # Use this ONLY if on Intel/AMD host

```

### D) Worker Credentials (`worker/client.conf`)

Generate a key/secret in the WebUI (Admin > Users) after the first start, then place them into `openqa/prod/config/worker/client.conf` before starting the worker service so the helper process can read your credentials.

```ini
[localhost]
key = <YOUR_API_KEY>
secret = <YOUR_API_SECRET>

```

---

## 3. Essential Fixes (Apply Once)

### Clone Test Distribution

The worker needs test code to run jobs.

```bash
cd openqa/prod/share/tests
# Clone distribution (rename to 'opensuse' for standard compatibility)
sudo git clone --depth 1 [https://github.com/os-autoinst/os-autoinst-distri-opensuse.git](https://github.com/os-autoinst/os-autoinst-distri-opensuse.git) opensuse
# Clone needles
cd opensuse/products/opensuse
sudo git clone --depth 1 [https://github.com/os-autoinst/os-autoinst-needles-opensuse.git](https://github.com/os-autoinst/os-autoinst-needles-opensuse.git) needles
# Fix permissions again
sudo chown -R 100494:165532 openqa/prod/share/tests

```

### Apache WebSocket Proxy Patch

Because WebSockets run in a separate container, we must patch the WebUI's Apache config.

1. Start `openqa-webui` once.
2. Extract the config:
```bash
podman exec openqa-prod-webui cat /etc/apache2/vhosts.d/openqa-common.inc > openqa/prod/config/apache2/vhosts.d/openqa-common.inc

```


3. Patch `localhost` -> `openqa-websockets`:
```bash
sed -i 's/localhost:9527/openqa-websockets:9527/g' openqa/prod/config/apache2/vhosts.d/openqa-common.inc

```



---

## 4. Docker Compose Specifics

Your `docker-compose.yml` MUST adhere to these rules to avoid known bugs:

1. **WebUI Volume must be Writable:**
* The WebUI container modifies config on startup.
* Map: `./config/etc-openqa:/etc/openqa:rw`


2. **WebSockets Config Mount:**
* Mount the directory, not files (avoids inode issues).
* Map: `./config/worker/workers.ini:/etc/openqa/workers.ini:ro` and `./config/worker/client.conf:/etc/openqa/client.conf:ro`


3. **Machine ID:**
* Pass host ID to avoid D-Bus errors.
* Map: `/etc/machine-id:/var/lib/dbus/machine-id:ro`



---

## 5. Operations

### Start/Restart

```bash
podman-compose down
podman-compose up -d

```

### Smoke Test (ARM64)

Verify the stack is working by cloning a small text-mode job.
*Requires `client.conf` to be valid.*

```bash
podman exec -it openqa-prod-webui \
  /usr/share/openqa/script/openqa-clone-job \
  --skip-download \
  --from [https://openqa.opensuse.org](https://openqa.opensuse.org) \
  --host localhost \
  --max-depth 0 \
  5629522 \
  Test=textmode-smoke-test \
  ARCH=aarch64

```

### Troubleshooting

* **WebUI 502/Bad Gateway:** Check `openqa-prod-webui` logs. Likely permission error on `/data/conf/database.ini`.
* **Worker "Terminated":** Check `WORKER_CLASS` in `workers.ini`. It defaults to x86; must be `qemu_aarch64` on ARM.
* **Worker "WebSocket 502":** Check `openqa-prod-websockets` logs. If it says "No configuration files supplied", ensure the `/etc/openqa` volume mount is correct and readable.
