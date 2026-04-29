# Game Website Practice Lab

This repo simulates a game backend made of an API gateway, multiple backend APIs, PostgreSQL databases, and Cassandra chat storage.

The local Docker Compose setup now mirrors the planned low-cost Azure shape:

- One API gateway container
- Multiple API containers using the same `game-website-mock-api` image
- One shared PostgreSQL container named `game-postgres`
- Separate PostgreSQL databases inside that one server
- One Cassandra container named `game-cassandra`
- Docker DNS between the gateway and internal APIs

The APIs are lightweight mock services. They keep API data in memory so you can practice routing, Docker, service discovery, and deployment without wiring a full ORM first.

## Local Architecture

| Local component | Local container/service | Azure equivalent |
| --- | --- | --- |
| API gateway | `api-gateway` / `game-api-gateway` | Azure Container App with external ingress |
| Backend APIs | `game-*-api` containers | Azure Container Apps with internal ingress |
| Shared PostgreSQL | `postgres` / `game-postgres` | Azure Database for PostgreSQL Flexible Server |
| Service databases | `security`, `profile`, `game`, `store`, `teams`, `matchup`, `tournaments` | Separate databases in the same PostgreSQL Flexible Server |
| Cassandra | `cassandra` / `game-cassandra` | Cassandra VM on Azure |

Gateway route format:

```text
http://localhost:5000/{service}/{backend-path}
```

Examples:

```powershell
Invoke-RestMethod http://localhost:5000/security/api/users
Invoke-RestMethod http://localhost:5000/profile/api/profiles
Invoke-RestMethod http://localhost:5000/game/api/games
```

## Start Locally

Clean start:

```powershell
docker compose down -v
docker compose up -d --build
```

Or run the validation script:

```powershell
.\scripts\test-local.ps1
```

The script:

- runs `docker compose up -d --build`
- waits for PostgreSQL and Cassandra
- prints `docker ps`
- tests gateway and API health endpoints from host ports
- checks internal Docker DNS from inside `api-gateway` if `curl` exists in the gateway image

## Local Ports

| Component | Host URL / port |
| --- | --- |
| API gateway | http://localhost:5000 |
| Security API | http://localhost:5015 |
| Profile API | http://localhost:5016 |
| Tournaments API | http://localhost:5017 |
| Teams API | http://localhost:5018 |
| Matchup API | http://localhost:5019 |
| Store API | http://localhost:5020 |
| Game API | http://localhost:5021 |
| Notification API | http://localhost:5022 |
| PostgreSQL | localhost:5432 |
| Cassandra | localhost:9042 |

## Verify PostgreSQL

PostgreSQL credentials:

```text
user: postgres
password: postgres
```

List databases:

```powershell
docker exec -it game-postgres psql -U postgres -c "\l"
```

Expected service databases:

```text
security
profile
game
store
teams
matchup
tournaments
```

The local init file is `db/init/001-create-databases.sql`. The existing schema practice files remain under `db/postgres/*.sql`; the mock APIs do not currently read tables from PostgreSQL.

## Verify Cassandra

```powershell
docker exec -it game-cassandra cqlsh -e "DESCRIBE KEYSPACES;"
```

TODO: the current app code does not define or read Cassandra-specific environment variables. Cassandra is included locally to simulate planned chat storage, but no notification/chat API code is wired to it yet.

## Test API Communication

Gateway health:

```powershell
Invoke-RestMethod http://localhost:5000/health
```

Backend health from the host:

```powershell
Invoke-RestMethod http://localhost:5015/health
Invoke-RestMethod http://localhost:5022/health
```

Gateway-to-service routing through Docker DNS:

```powershell
Invoke-RestMethod http://localhost:5000/security/api/users
Invoke-RestMethod http://localhost:5000/store/api/products
Invoke-RestMethod http://localhost:5000/teams/api/teams
```

Gateway environment variables point to Docker service names:

```text
SECURITY_API_URL=http://game-security-api:8080
PROFILE_API_URL=http://game-profile-api:8080
GAME_API_URL=http://game-game-api:8080
STORE_API_URL=http://game-store-api:8080
TEAMS_API_URL=http://game-teams-api:8080
MATCHUP_API_URL=http://game-matchup-api:8080
TOURNAMENTS_API_URL=http://game-tournaments-api:8080
NOTIFICATION_API_URL=http://game-notification-api:8080
```

## GitHub Actions Images

The workflow in `.github/workflows/docker-images.yml` still builds and pushes:

```text
ghcr.io/vusallmammad/game-website-api-gateway:latest
ghcr.io/vusallmammad/game-website-mock-api:latest
```

It uses the automatic `GITHUB_TOKEN` with:

```yaml
permissions:
  contents: read
  packages: write
```

No Azure Container Registry is used.

## Azure Deployment

The script `scripts/deploy-aca.ps1` deploys the low-cost Azure version:

- API gateway and APIs on Azure Container Apps
- One Azure Database for PostgreSQL Flexible Server
- Separate databases inside the same PostgreSQL server
- GHCR images directly, not Azure Container Registry
- No Azure Storage Account
- No Cassandra deployment for now

Run:

```powershell
az login

$env:POSTGRES_ADMIN_PASSWORD = '<use-a-strong-password>'

.\scripts\deploy-aca.ps1 `
  -ResourceGroup rg-game-website `
  -Location eastus `
  -PostgresServerName pg-game-website `
  -PostgresAdminUser gameadmin `
  -PostgresAdminPassword $env:POSTGRES_ADMIN_PASSWORD `
  -GitHubOwner vusallmammad `
  -ImageTag latest
```

For private GHCR packages:

```powershell
$env:GHCR_USERNAME = 'vusallmammad'
$env:GHCR_TOKEN = '<github-pat-with-read-packages>'
```

Then run the same deployment command.

## Build Without Docker

On this machine the user-level NuGet config may be locked, so these commands keep .NET and NuGet state inside the repo:

```powershell
$root = (Resolve-Path .).Path
$env:DOTNET_CLI_HOME = $root
$env:APPDATA = $root
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
dotnet restore src/GameWebsite.MockApi/GameWebsite.MockApi.csproj --configfile NuGet.Config
dotnet restore src/GameWebsite.ApiGateway/GameWebsite.ApiGateway.csproj --configfile NuGet.Config
dotnet build GameWebsitePractice.sln --no-restore -m:1
```

## Cleanup

Local:

```powershell
docker compose down -v
```

Azure:

```powershell
az group delete -n rg-game-website --yes
```
