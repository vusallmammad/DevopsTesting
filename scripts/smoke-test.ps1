param(
    [string]$BaseUrl = "http://localhost:5000"
)

$ErrorActionPreference = "Stop"

$paths = @(
    "/",
    "/routes",
    "/health",
    "/security/api/users",
    "/profile/api/profiles",
    "/game/api/games",
    "/store/api/products",
    "/notification/api/notifications",
    "/tournaments/api/tournaments",
    "/matchup/api/matches",
    "/teams/api/teams"
)

foreach ($path in $paths) {
    Write-Host "GET $path"
    Invoke-RestMethod -Uri "$BaseUrl$path" -Method Get | ConvertTo-Json -Depth 8
}

Write-Host "POST /security/api/auth/login"
$loginBody = @{ userName = "demo"; password = "demo" } | ConvertTo-Json
Invoke-RestMethod -Uri "$BaseUrl/security/api/auth/login" -Method Post -ContentType "application/json" -Body $loginBody |
    ConvertTo-Json -Depth 8
