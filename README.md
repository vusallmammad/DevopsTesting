# Game Website Practice Lab

This repo simulates the API and database shape from the screenshot: an API gateway, eight backend APIs, seven local PostgreSQL containers, and one local Cassandra chat database.

For Azure, the deployment is intentionally cheaper than the full local topology:

- GitHub Actions builds Docker images.
- Images are pushed to GitHub Container Registry, `ghcr.io`.
- Azure Container Apps runs the gateway and APIs.
- One Azure Database for PostgreSQL Flexible Server hosts separate databases per service.
- No Azure Container Registry, no PostgreSQL containers in Azure, no Cassandra in Azure for now, and no Azure Storage Account.

The APIs are lightweight mock services. They keep API data in memory so you can practice routing, Docker, ports, service discovery, and deployment without wiring a full ORM first. The PostgreSQL schemas are still real and can be applied to the managed Azure PostgreSQL databases.

## Local Topology

| Component | Local URL / port | Backing data |
| --- | --- | --- |
| API gateway | http://localhost:5000 | Routes to backend APIs |
| Security API | http://localhost:5015 | `security-db` on localhost:5433 |
| Profile API | http://localhost:5016 | `profile-db` on localhost:5434 |
| Tournaments API | http://localhost:5017 | `tournaments-db` on localhost:5439 |
| Teams API | http://localhost:5018 | `teams-db` on localhost:5437 |
| Matchup API | http://localhost:5019 | `matchup-db` on localhost:5438 |
| Store API | http://localhost:5020 | `store-db` on localhost:5436 |
| Game API | http://localhost:5021 | `game-db` on localhost:5435 |
| Notification API | http://localhost:5022 | In-memory mock |
| Chat DB | localhost:9042 | Local Cassandra keyspace `game_chat` |

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

## Run Locally

```powershell
docker compose up --build -d
docker compose ps
.\scripts\smoke-test.ps1
```

Useful endpoints:

```text
GET  http://localhost:5000/routes
GET  http://localhost:5000/health
GET  http://localhost:5000/security/api/users
POST http://localhost:5000/security/api/auth/login
GET  http://localhost:5000/teams/api/teams
POST http://localhost:5000/teams/api/teams/team-001/members
```

The request collection in `samples/game-website.http` works with VS Code REST Client, Rider, or similar HTTP file tooling.

## GitHub Actions Images

The workflow in `.github/workflows/docker-images.yml` builds and pushes these images to GitHub Container Registry on pushes to `main`:

```text
ghcr.io/vusallmammad/game-website-api-gateway:latest
ghcr.io/vusallmammad/game-website-mock-api:latest
```

The workflow uses the automatic `GITHUB_TOKEN` and declares:

```yaml
permissions:
  contents: read
  packages: write
```

No GitHub Actions secrets are required for the image build and push.

Pull locally after the workflow runs:

```powershell
docker pull ghcr.io/vusallmammad/game-website-api-gateway:latest
docker pull ghcr.io/vusallmammad/game-website-mock-api:latest
```

GHCR visibility note: Azure Container Apps can pull public GHCR images without credentials. If the GHCR packages are private, create a GitHub PAT with `read:packages`, then run the deploy script with `GHCR_USERNAME` and `GHCR_TOKEN` environment variables set.

## Database Practice

PostgreSQL credentials for all local DBs:

```text
user: game
password: game_dev_password
```

Examples:

```powershell
docker exec -it game-security-db psql -U game -d security
docker exec -it game-game-db psql -U game -d game
docker exec -it game-chat-db cqlsh
```

Cassandra is local-only for now. Query after opening `cqlsh`:

```sql
USE game_chat;
SELECT * FROM messages_by_room WHERE room_id = 'room-001';
```

Schema files live in:

```text
db/postgres/*.sql
db/cassandra/chat.cql
```

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

## Azure Deployment

The script `scripts/deploy-aca.ps1` creates or reuses:

- Resource group: `rg-game-website`
- Container Apps environment: `cae-game-website`
- PostgreSQL Flexible Server: `pg-game-website`
- PostgreSQL SKU: `Standard_B1ms`, Burstable tier
- PostgreSQL version: `16`
- PostgreSQL storage: `32 GB`
- Backup retention: `7 days`
- High availability: disabled
- Container Apps logs destination: `none`, to avoid Log Analytics cost
- API replicas: min `0`, max `1`, `0.25` CPU, `0.5Gi` memory

It creates these databases inside the same PostgreSQL server:

```text
security
profile
game
store
teams
matchup
tournaments
```

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

## SQL Initialization

The deploy script creates all seven databases. If `psql` exists locally, the script temporarily allows your current public IP on the PostgreSQL firewall, runs these SQL files, then removes the temporary firewall rule:

```text
db/postgres/security.sql -> security
db/postgres/profile.sql -> profile
db/postgres/game.sql -> game
db/postgres/store.sql -> store
db/postgres/teams.sql -> teams
db/postgres/matchup.sql -> matchup
db/postgres/tournaments.sql -> tournaments
```

If `psql` is not available, the script prints the exact `psql` commands to run manually.

## Estimated Monthly Cost

For light practice use, cost should be dominated by Azure Database for PostgreSQL Flexible Server. A rough estimate in many US regions is low tens of USD per month for `Standard_B1ms` plus 32 GB storage. Azure Container Apps are configured with min replicas `0`, so idle API cost should be near zero and small traffic may fit inside the monthly free grants.

Pricing changes by region and account type. Check the Azure Pricing Calculator before leaving resources running.

## Cleanup

```powershell
az group delete -n rg-game-website --yes
```

## References

- Azure Container Apps ingress supports internal and external ingress: https://learn.microsoft.com/azure/container-apps/ingress-overview
- Container apps can call other apps in the same environment by app name: https://learn.microsoft.com/azure/container-apps/connect-apps
- Container Apps environment logs can be set to `none`: https://learn.microsoft.com/azure/container-apps/log-options
- PostgreSQL Flexible Server can use public access with the `0.0.0.0` Azure-services firewall rule: https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-firewall-rules
