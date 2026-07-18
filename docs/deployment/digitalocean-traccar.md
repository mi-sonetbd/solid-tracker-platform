# DigitalOcean backend and Traccar deployment foundation

This foundation runs the Solid Tracker API, PostgreSQL, Redis, Traccar, and
Caddy on one Docker Compose host. It does not store real secrets in Git and it
does not expose PostgreSQL, Redis, or the Traccar administration UI publicly.

## Public network surface

| Port | Exposure | Purpose |
| --- | --- | --- |
| 22/TCP | Administrator IP only | SSH |
| 80/TCP | Public | HTTPS certificate redirect/challenge |
| 443/TCP | Public | Solid Tracker API |
| Tracker protocol port | Public | GPS device TCP/UDP traffic |
| 8082/TCP | Loopback only | Traccar administration through an SSH tunnel |
| 5432/TCP | Not published | PostgreSQL |
| 6379/TCP | Not published | Redis |

Do not publish Traccar's full protocol range. Set the one exact port required
by the selected physical GPS tracker model.

## Files

- `compose.production.yaml` defines the production services and private network.
- `production.env.example` lists required values but contains no usable secrets.
- `services/backend-api/Dockerfile` builds and starts the API and runs Prisma
  deployment migrations before startup.
- `infrastructure/postgres/init/01-create-traccar-database.sh` creates a separate
  Traccar database and login during first PostgreSQL initialization.
- `infrastructure/caddy/Caddyfile` terminates HTTPS for the public API.

## Before provisioning the Droplet

1. Choose an API domain and create its DNS A record after the Droplet exists.
2. Confirm the GPS tracker manufacturer/model, Traccar protocol, and exact port.
3. Keep `TRACCAR_SERVER_CODE` as a placeholder until the Traccar server record
   is registered through the Solid Tracker backend.
4. Generate the real production environment file outside the Git checkout.

The planned server paths are:

- Application checkout: `/opt/solid-tracker/app`
- Secret environment: `/opt/solid-tracker/shared/production.env`
- Backups: `/opt/solid-tracker/backups`

## Local validation

```powershell
docker compose --env-file production.env.example -f compose.production.yaml config --quiet
docker compose --env-file production.env.example -f compose.production.yaml build backend-api
```

The example environment must never be used for a real deployment.

## Official references

- Traccar Docker: https://www.traccar.org/docker/
- Traccar forwarding: https://www.traccar.org/forward/
- Traccar configuration: https://www.traccar.org/configuration-file/
- DigitalOcean SSH: https://docs.digitalocean.com/products/droplets/how-to/connect-with-ssh/
- DigitalOcean SSH keys: https://docs.digitalocean.com/products/droplets/how-to/add-ssh-keys/
