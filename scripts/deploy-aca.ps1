param(
    [string]$ResourceGroup = "rg-game-website-practice",
    [string]$Location = "eastus",
    [string]$ContainerAppsEnvironment = "game-practice-env",
    [string]$AcrName = "",
    [string]$ImageTag = "v1"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AcrName)) {
    $AcrName = ("gamepractice" + (Get-Random -Minimum 10000 -Maximum 99999)).ToLowerInvariant()
}

Write-Host "Using Azure Container Registry: $AcrName"

az extension add --name containerapp --upgrade
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

az group create --name $ResourceGroup --location $Location
az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true

$loginServer = az acr show --resource-group $ResourceGroup --name $AcrName --query loginServer -o tsv
$acrUser = az acr credential show --name $AcrName --query username -o tsv
$acrPass = az acr credential show --name $AcrName --query "passwords[0].value" -o tsv

az acr build --registry $AcrName --image "game-website-mock-api:$ImageTag" --file src/GameWebsite.MockApi/Dockerfile .
az acr build --registry $AcrName --image "game-website-api-gateway:$ImageTag" --file src/GameWebsite.ApiGateway/Dockerfile .

az containerapp env create `
    --name $ContainerAppsEnvironment `
    --resource-group $ResourceGroup `
    --location $Location

$services = @(
    @{ Name = "game-security-api"; Key = "security"; Title = "Security API"; DbKind = "postgres"; DbHost = "security-db"; DbName = "security"; EnvName = "SECURITY_API_URL" },
    @{ Name = "game-profile-api"; Key = "profile"; Title = "Profile API"; DbKind = "postgres"; DbHost = "profile-db"; DbName = "profile"; EnvName = "PROFILE_API_URL" },
    @{ Name = "game-game-api"; Key = "game"; Title = "Game API"; DbKind = "postgres"; DbHost = "game-db"; DbName = "game"; EnvName = "GAME_API_URL" },
    @{ Name = "game-store-api"; Key = "store"; Title = "Store API"; DbKind = "postgres"; DbHost = "store-db"; DbName = "store"; EnvName = "STORE_API_URL" },
    @{ Name = "game-notification-api"; Key = "notification"; Title = "Notification API"; DbKind = "memory"; DbHost = "notification-memory"; DbName = "notification"; EnvName = "NOTIFICATION_API_URL" },
    @{ Name = "game-tournaments-api"; Key = "tournaments"; Title = "Tournaments API"; DbKind = "postgres"; DbHost = "tournaments-db"; DbName = "tournaments"; EnvName = "TOURNAMENTS_API_URL" },
    @{ Name = "game-matchup-api"; Key = "matchup"; Title = "Matchup API"; DbKind = "postgres"; DbHost = "matchup-db"; DbName = "matchup"; EnvName = "MATCHUP_API_URL" },
    @{ Name = "game-teams-api"; Key = "teams"; Title = "Teams API"; DbKind = "postgres"; DbHost = "teams-db"; DbName = "teams"; EnvName = "TEAMS_API_URL" }
)

foreach ($service in $services) {
    Write-Host "Creating internal app $($service.Name)"
    $envVars = @(
        "ASPNETCORE_URLS=http://+:8080",
        "SERVICE_KEY=$($service.Key)",
        "SERVICE_TITLE=$($service.Title)",
        "DB_KIND=$($service.DbKind)",
        "DB_HOST=$($service.DbHost)",
        "DB_NAME=$($service.DbName)",
        "DB_PORT=5432",
        "DB_USER=game"
    )

    az containerapp create `
        --name $service.Name `
        --resource-group $ResourceGroup `
        --environment $ContainerAppsEnvironment `
        --image "$loginServer/game-website-mock-api:$ImageTag" `
        --target-port 8080 `
        --ingress internal `
        --registry-server $loginServer `
        --registry-username $acrUser `
        --registry-password $acrPass `
        --min-replicas 0 `
        --max-replicas 1 `
        --env-vars $envVars
}

$gatewayEnvVars = @("ASPNETCORE_URLS=http://+:8080")
foreach ($service in $services) {
    $gatewayEnvVars += "$($service.EnvName)=http://$($service.Name)"
}

Write-Host "Creating public gateway"
az containerapp create `
    --name game-api-gateway `
    --resource-group $ResourceGroup `
    --environment $ContainerAppsEnvironment `
    --image "$loginServer/game-website-api-gateway:$ImageTag" `
    --target-port 8080 `
    --ingress external `
    --registry-server $loginServer `
    --registry-username $acrUser `
    --registry-password $acrPass `
    --min-replicas 0 `
    --max-replicas 1 `
    --env-vars $gatewayEnvVars

$gatewayFqdn = az containerapp show `
    --name game-api-gateway `
    --resource-group $ResourceGroup `
    --query "properties.configuration.ingress.fqdn" `
    -o tsv

Write-Host ""
Write-Host "Gateway URL: https://$gatewayFqdn"
Write-Host "Try: https://$gatewayFqdn/security/api/users"
