param(
    [string]$ResourceGroup = "rg-game-website",
    [string]$Location = "eastus",
    [string]$PostgresServerName = "pg-game-website",
    [string]$PostgresAdminUser = "gameadmin",
    [Parameter(Mandatory = $true)]
    [string]$PostgresAdminPassword,
    [string]$GitHubOwner = "vusallmammad",
    [string]$ImageTag = "latest",
    [string]$ContainerAppsEnvironment = "cae-game-website",
    [string]$GhcrUsername = $env:GHCR_USERNAME,
    [string]$GhcrToken = $env:GHCR_TOKEN,
    [switch]$SkipSqlInitialization
)

$ErrorActionPreference = "Stop"

$postgresDatabases = @(
    @{ Name = "security"; SqlFile = "db/postgres/security.sql" },
    @{ Name = "profile"; SqlFile = "db/postgres/profile.sql" },
    @{ Name = "game"; SqlFile = "db/postgres/game.sql" },
    @{ Name = "store"; SqlFile = "db/postgres/store.sql" },
    @{ Name = "teams"; SqlFile = "db/postgres/teams.sql" },
    @{ Name = "matchup"; SqlFile = "db/postgres/matchup.sql" },
    @{ Name = "tournaments"; SqlFile = "db/postgres/tournaments.sql" }
)

$apis = @(
    @{ Name = "game-security-api"; Key = "security"; Title = "Security API"; DbName = "security"; EnvName = "SECURITY_API_URL" },
    @{ Name = "game-profile-api"; Key = "profile"; Title = "Profile API"; DbName = "profile"; EnvName = "PROFILE_API_URL" },
    @{ Name = "game-game-api"; Key = "game"; Title = "Game API"; DbName = "game"; EnvName = "GAME_API_URL" },
    @{ Name = "game-store-api"; Key = "store"; Title = "Store API"; DbName = "store"; EnvName = "STORE_API_URL" },
    @{ Name = "game-teams-api"; Key = "teams"; Title = "Teams API"; DbName = "teams"; EnvName = "TEAMS_API_URL" },
    @{ Name = "game-matchup-api"; Key = "matchup"; Title = "Matchup API"; DbName = "matchup"; EnvName = "MATCHUP_API_URL" },
    @{ Name = "game-tournaments-api"; Key = "tournaments"; Title = "Tournaments API"; DbName = "tournaments"; EnvName = "TOURNAMENTS_API_URL" },
    @{ Name = "game-notification-api"; Key = "notification"; Title = "Notification API"; DbKind = "memory"; EnvName = "NOTIFICATION_API_URL" }
)

function Invoke-Az {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
}

function Get-AzTsv {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $value = & az @Arguments -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ') -o tsv"
    }

    return ($value | Out-String).Trim()
}

function Test-AzResource {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & az @Arguments -o none 2>$null
    return $LASTEXITCODE -eq 0
}

function Ensure-PostgresFirewallRule {
    param(
        [Parameter(Mandatory = $true)][string]$RuleName,
        [Parameter(Mandatory = $true)][string]$StartIpAddress,
        [Parameter(Mandatory = $true)][string]$EndIpAddress
    )

    $ruleExists = Test-AzResource @(
        "postgres", "flexible-server", "firewall-rule", "show",
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--rule-name", $RuleName
    )

    if ($ruleExists) {
        Invoke-Az @(
            "postgres", "flexible-server", "firewall-rule", "update",
            "--resource-group", $ResourceGroup,
            "--name", $PostgresServerName,
            "--rule-name", $RuleName,
            "--start-ip-address", $StartIpAddress,
            "--end-ip-address", $EndIpAddress
        )
        return
    }

    Invoke-Az @(
        "postgres", "flexible-server", "firewall-rule", "create",
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--rule-name", $RuleName,
        "--start-ip-address", $StartIpAddress,
        "--end-ip-address", $EndIpAddress
    )
}

function Add-RegistryArgs {
    param([string[]]$Arguments)

    if ([string]::IsNullOrWhiteSpace($GhcrUsername) -or [string]::IsNullOrWhiteSpace($GhcrToken)) {
        return $Arguments
    }

    return $Arguments + @(
        "--registry-server", "ghcr.io",
        "--registry-username", $GhcrUsername,
        "--registry-password", $GhcrToken
    )
}

function New-PostgresEnvVars {
    param([hashtable]$Api, [string]$PostgresFqdn)

    if (($Api.ContainsKey("DbKind") -and $Api.DbKind -eq "memory")) {
        return @(
            "ASPNETCORE_URLS=http://+:8080",
            "SERVICE_KEY=$($Api.Key)",
            "SERVICE_TITLE=$($Api.Title)",
            "DB_KIND=memory"
        )
    }

    return @(
        "ASPNETCORE_URLS=http://+:8080",
        "SERVICE_KEY=$($Api.Key)",
        "SERVICE_TITLE=$($Api.Title)",
        "DB_KIND=postgres",
        "DB_HOST=$PostgresFqdn",
        "DB_PORT=5432",
        "DB_USER=$PostgresAdminUser",
        "DB_PASSWORD=secretref:db-password",
        "DB_NAME=$($Api.DbName)",
        "DB_SSLMODE=require"
    )
}

function Deploy-ContainerApp {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Image,
        [Parameter(Mandatory = $true)][ValidateSet("external", "internal")][string]$Ingress,
        [Parameter(Mandatory = $true)][string[]]$EnvVars,
        [string[]]$Secrets = @()
    )

    $exists = Test-AzResource @("containerapp", "show", "--name", $Name, "--resource-group", $ResourceGroup)

    if ($exists) {
        Write-Host "Updating Container App: $Name"

        if (-not [string]::IsNullOrWhiteSpace($GhcrUsername) -and -not [string]::IsNullOrWhiteSpace($GhcrToken)) {
            Invoke-Az @(
                "containerapp", "registry", "set",
                "--name", $Name,
                "--resource-group", $ResourceGroup,
                "--server", "ghcr.io",
                "--username", $GhcrUsername,
                "--password", $GhcrToken
            )
        }

        if ($Secrets.Count -gt 0) {
            $secretArgs = @(
                "containerapp", "secret", "set",
                "--name", $Name,
                "--resource-group", $ResourceGroup,
                "--secrets"
            )
            $secretArgs += $Secrets
            Invoke-Az $secretArgs
        }

        $updateArgs = @(
            "containerapp", "update",
            "--name", $Name,
            "--resource-group", $ResourceGroup,
            "--image", $Image,
            "--cpu", "0.25",
            "--memory", "0.5Gi",
            "--min-replicas", "0",
            "--max-replicas", "1",
            "--replace-env-vars"
        )
        $updateArgs += $EnvVars
        Invoke-Az $updateArgs

        Invoke-Az @(
            "containerapp", "ingress", "enable",
            "--name", $Name,
            "--resource-group", $ResourceGroup,
            "--type", $Ingress,
            "--target-port", "8080",
            "--transport", "auto"
        )

        return
    }

    Write-Host "Creating Container App: $Name"
    $createArgs = @(
        "containerapp", "create",
        "--name", $Name,
        "--resource-group", $ResourceGroup,
        "--environment", $ContainerAppsEnvironment,
        "--image", $Image,
        "--target-port", "8080",
        "--ingress", $Ingress,
        "--transport", "auto",
        "--revisions-mode", "single",
        "--cpu", "0.25",
        "--memory", "0.5Gi",
        "--min-replicas", "0",
        "--max-replicas", "1"
    )

    $createArgs = Add-RegistryArgs $createArgs

    if ($Secrets.Count -gt 0) {
        $createArgs += @("--secrets")
        $createArgs += $Secrets
    }

    $createArgs += @("--env-vars")
    $createArgs += $EnvVars

    Invoke-Az $createArgs
}

function Write-ManualSqlCommands {
    param([string]$PostgresFqdn)

    Write-Host ""
    Write-Host "SQL initialization was not run automatically."
    Write-Host "After allowing your client IP on the PostgreSQL server firewall, run:"
    Write-Host ""

    foreach ($database in $postgresDatabases) {
        $sqlPath = $database.SqlFile.Replace("/", "\")
        Write-Host "`$env:PGPASSWORD = '<postgres-admin-password>'"
        Write-Host "psql `"host=$PostgresFqdn port=5432 dbname=$($database.Name) user=$PostgresAdminUser sslmode=require`" -f .\$sqlPath"
        Write-Host ""
    }
}

function Initialize-PostgresSchemas {
    param([string]$PostgresFqdn)

    if ($SkipSqlInitialization) {
        Write-ManualSqlCommands $PostgresFqdn
        return
    }

    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if ($null -eq $psql) {
        Write-Host "psql was not found on PATH."
        Write-ManualSqlCommands $PostgresFqdn
        return
    }

    $clientIp = $null
    try {
        $clientIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    }
    catch {
        Write-Host "Could not detect local public IP for temporary PostgreSQL firewall rule."
        Write-ManualSqlCommands $PostgresFqdn
        return
    }

    $temporaryRuleName = "AllowLocalPsqlInit"
    Write-Host "Temporarily allowing local IP $clientIp for SQL initialization."
    Ensure-PostgresFirewallRule -RuleName $temporaryRuleName -StartIpAddress $clientIp -EndIpAddress $clientIp

    $previousPassword = $env:PGPASSWORD
    $env:PGPASSWORD = $PostgresAdminPassword

    try {
        foreach ($database in $postgresDatabases) {
            Write-Host "Applying $($database.SqlFile) to database '$($database.Name)'"
            & $psql.Source "host=$PostgresFqdn port=5432 dbname=$($database.Name) user=$PostgresAdminUser sslmode=require" -f $database.SqlFile
            if ($LASTEXITCODE -ne 0) {
                throw "psql failed for database '$($database.Name)'"
            }
        }
    }
    finally {
        if ($null -eq $previousPassword) {
            Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
        }
        else {
            $env:PGPASSWORD = $previousPassword
        }

        Write-Host "Removing temporary local PostgreSQL firewall rule."
        & az postgres flexible-server firewall-rule delete `
            --resource-group $ResourceGroup `
            --name $PostgresServerName `
            --rule-name $temporaryRuleName `
            --yes `
            -o none 2>$null
    }
}

$normalizedOwner = $GitHubOwner.ToLowerInvariant()
$mockApiImage = "ghcr.io/$normalizedOwner/game-website-mock-api:$ImageTag"
$gatewayImage = "ghcr.io/$normalizedOwner/game-website-api-gateway:$ImageTag"

Write-Host "Deploying minimum-cost Azure resources"
Write-Host "Resource group: $ResourceGroup"
Write-Host "Container Apps environment: $ContainerAppsEnvironment"
Write-Host "PostgreSQL server: $PostgresServerName"
Write-Host "Mock API image: $mockApiImage"
Write-Host "Gateway image: $gatewayImage"

Invoke-Az @("extension", "add", "--name", "containerapp", "--upgrade")
Invoke-Az @("provider", "register", "--namespace", "Microsoft.App")
Invoke-Az @("provider", "register", "--namespace", "Microsoft.DBforPostgreSQL")

Invoke-Az @("group", "create", "--name", $ResourceGroup, "--location", $Location)

$environmentExists = Test-AzResource @(
    "containerapp", "env", "show",
    "--name", $ContainerAppsEnvironment,
    "--resource-group", $ResourceGroup
)

if ($environmentExists) {
    Write-Host "Reusing Container Apps environment: $ContainerAppsEnvironment"
}
else {
    Write-Host "Creating Container Apps environment without Log Analytics to minimize cost."
    Invoke-Az @(
        "containerapp", "env", "create",
        "--name", $ContainerAppsEnvironment,
        "--resource-group", $ResourceGroup,
        "--location", $Location,
        "--logs-destination", "none",
        "--enable-workload-profiles", "false"
    )
}

$postgresExists = Test-AzResource @(
    "postgres", "flexible-server", "show",
    "--resource-group", $ResourceGroup,
    "--name", $PostgresServerName
)

if ($postgresExists) {
    Write-Host "Reusing PostgreSQL Flexible Server: $PostgresServerName"
    Invoke-Az @(
        "postgres", "flexible-server", "update",
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--admin-password", $PostgresAdminPassword,
        "--sku-name", "Standard_B1ms",
        "--tier", "Burstable",
        "--storage-auto-grow", "Disabled",
        "--backup-retention", "7",
        "--public-access", "Enabled",
        "--yes"
    )
    Write-Host "Existing PostgreSQL storage size is reused. Azure does not allow shrinking storage to 32 GB."
}
else {
    Write-Host "Creating PostgreSQL Flexible Server: $PostgresServerName"
    Invoke-Az @(
        "postgres", "flexible-server", "create",
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--location", $Location,
        "--admin-user", $PostgresAdminUser,
        "--admin-password", $PostgresAdminPassword,
        "--version", "16",
        "--sku-name", "Standard_B1ms",
        "--tier", "Burstable",
        "--storage-size", "32",
        "--storage-auto-grow", "Disabled",
        "--backup-retention", "7",
        "--geo-redundant-backup", "Disabled",
        "--high-availability", "Disabled",
        "--public-access", "0.0.0.0",
        "--create-default-database", "Disabled",
        "--yes"
    )
}

Ensure-PostgresFirewallRule -RuleName "AllowAzureServices" -StartIpAddress "0.0.0.0" -EndIpAddress "0.0.0.0"

$postgresFqdn = Get-AzTsv @(
    "postgres", "flexible-server", "show",
    "--resource-group", $ResourceGroup,
    "--name", $PostgresServerName,
    "--query", "fullyQualifiedDomainName"
)

foreach ($database in $postgresDatabases) {
    $dbExists = Test-AzResource @(
        "postgres", "flexible-server", "db", "show",
        "--resource-group", $ResourceGroup,
        "--server-name", $PostgresServerName,
        "--database-name", $database.Name
    )

    if ($dbExists) {
        Write-Host "Reusing PostgreSQL database: $($database.Name)"
    }
    else {
        Write-Host "Creating PostgreSQL database: $($database.Name)"
        Invoke-Az @(
            "postgres", "flexible-server", "db", "create",
            "--resource-group", $ResourceGroup,
            "--server-name", $PostgresServerName,
            "--database-name", $database.Name
        )
    }
}

Initialize-PostgresSchemas $postgresFqdn

foreach ($api in $apis) {
    $envVars = New-PostgresEnvVars -Api $api -PostgresFqdn $postgresFqdn
    $secrets = @()

    if (-not ($api.ContainsKey("DbKind") -and $api.DbKind -eq "memory")) {
        $secrets = @("db-password=$PostgresAdminPassword")
    }

    Deploy-ContainerApp `
        -Name $api.Name `
        -Image $mockApiImage `
        -Ingress "internal" `
        -EnvVars $envVars `
        -Secrets $secrets
}

$gatewayEnvVars = @(
    "ASPNETCORE_URLS=http://+:8080",
    "SECURITY_API_URL=http://game-security-api",
    "PROFILE_API_URL=http://game-profile-api",
    "GAME_API_URL=http://game-game-api",
    "STORE_API_URL=http://game-store-api",
    "TEAMS_API_URL=http://game-teams-api",
    "MATCHUP_API_URL=http://game-matchup-api",
    "TOURNAMENTS_API_URL=http://game-tournaments-api",
    "NOTIFICATION_API_URL=http://game-notification-api"
)

Deploy-ContainerApp `
    -Name "game-api-gateway" `
    -Image $gatewayImage `
    -Ingress "external" `
    -EnvVars $gatewayEnvVars

$gatewayFqdn = Get-AzTsv @(
    "containerapp", "show",
    "--name", "game-api-gateway",
    "--resource-group", $ResourceGroup,
    "--query", "properties.configuration.ingress.fqdn"
)

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Gateway URL: https://$gatewayFqdn"
Write-Host "Try: https://$gatewayFqdn/security/api/users"
Write-Host ""
Write-Host "Cleanup:"
Write-Host "az group delete -n $ResourceGroup --yes"
