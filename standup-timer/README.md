# Stand-up Timer Stack

This stack manages the deployment of the Stand-up Timer application.

## Maintenance Operations

If you update the source code in `/home/orangepi/standup-timer/`, follow these steps to redeploy:

### Redeploy (Code/Dependency/Environment Updates)
Since the source code is bind-mounted, a restart picks up code changes. However, **you must reload Nginx** afterward because Podman changes the internal IP of the container on restart.

```bash
# 1. Restart the app
cd ~/podman-compose/standup-timer
podman-compose restart

# 2. Sync Nginx (Essential for DNS resolution)
podman exec nginx nginx -s reload
```

### Full Recreation
If you have added new npm packages or changed the `.env` file:
```bash
cd ~/podman-compose/standup-timer
podman-compose down
podman-compose up -d
podman exec nginx nginx -s reload
```

### Viewing Logs
```bash
podman logs -f standup-timer
```
