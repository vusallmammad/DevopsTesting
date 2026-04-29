# Game Website Practice Lab

This repo simulates the API and database shape from the screenshot: an API gateway, eight backend APIs, seven PostgreSQL databases, and one Cassandra chat database.

The APIs are intentionally lightweight mock services. They keep API data in memory so you can practice routing, Docker, ports, service discovery, and deployment without first wiring a full ORM. The database containers still create real schemas and seed data for SQL/CQL practice.

## Topology

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
| Chat DB | localhost:9042 | Cassandra keyspace `game_chat` |

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
```

Smoke test:

```powershell
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

The workflow in `.github/workflows/docker-images.yml` builds and pushes two images to GitHub Container Registry when code is pushed to `main`:

```text
ghcr.io/vusallmammad/game-website-api-gateway:latest
ghcr.io/vusallmammad/game-website-mock-api:latest
```

The backend services in `docker-compose.yml` all use the same mock API image with different environment variables, so only one backend API image is needed.

Pull locally after the workflow runs:

```powershell
docker pull ghcr.io/vusallmammad/game-website-api-gateway:latest
docker pull ghcr.io/vusallmammad/game-website-mock-api:latest
```

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

Cassandra query after opening `cqlsh`:

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

## Azure Container Apps

Yes, this can be hosted on Azure Container Apps. The recommended practice setup is:

1. Deploy the gateway with external ingress.
2. Deploy each backend API with internal ingress.
3. Let the gateway call backends by Container App name, for example `http://game-security-api`.
4. Use managed databases for a real deployment: Azure Database for PostgreSQL for the Postgres services, and Cosmos DB Cassandra API or another managed Cassandra-compatible service for chat.

Run the starter deployment script:

```powershell
az login
.\scripts\deploy-aca.ps1 -ResourceGroup rg-game-website-practice -Location eastus
```

The script deploys the stateless APIs and gateway. It does not deploy database containers to Azure Container Apps, because production-style database hosting should use managed database services.

Microsoft docs used for the ACA shape:

- Container apps in the same environment can call each other by app name: https://learn.microsoft.com/azure/container-apps/connect-apps
- Container Apps supports external and internal ingress: https://learn.microsoft.com/azure/container-apps/ingress-overview

## Practice Ideas

- Add real persistence to one API with Npgsql and the matching Postgres schema.
- Add authentication checks in the gateway before forwarding requests.
- Add new service routes, for example a `chat-api` that reads from Cassandra.
- Convert the compose setup into separate ACA apps plus Azure managed databases.
