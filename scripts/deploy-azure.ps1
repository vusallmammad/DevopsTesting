param(
    [string]$ResourceGroup = "rg-game",
    [string]$Location = "eastus",
    [string]$ContainerAppsEnvironment = "cae-game",
    [string]$PostgresServerName = "pg-game",
    [string]$PostgresAdminUser = "gameadmin",
    [Parameter(Mandatory = $true)]
    [string]$PostgresAdminPassword,
    [string]$GitHubOwner = "vusallmammad",
    [string]$ImageTag = "latest",
    [string]$GhcrUsername = $env:GHCR_USERNAME,
    [string]$GhcrToken = $env:GHCR_TOKEN,
    [string]$CassandraVmName = "vm-cassandra",
    [string]$CassandraVmSize = "Standard_B2s",
    [string]$VmAdminUser = "azureuser",
    [string]$SshPublicKeyPath = "$HOME/.ssh/id_rsa.pub",
    [switch]$SkipCassandraInstall
)

$ErrorActionPreference = "Stop"

$vnetName = "vnet-game"
$containerAppsSubnetName = "snet-containerapps"
$cassandraSubnetName = "snet-cassandra"
$cassandraNsgName = "nsg-cassandra"
$cassandraNicName = "nic-cassandra"
$mockApiImage = "ghcr.io/$($GitHubOwner.ToLowerInvariant())/game-website-mock-api:$ImageTag"
$gatewayImage = "ghcr.io/$($GitHubOwner.ToLowerInvariant())/game-website-api-gateway:$ImageTag"

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

function Wait-AzProvider {
    param([Parameter(Mandatory = $true)][string]$Namespace)

    Write-Host "Registering provider: $Namespace"
    Invoke-Az @("provider", "register", "--namespace", $Namespace)

    for ($i = 1; $i -le 60; $i++) {
        $state = Get-AzTsv @(
            "provider", "show",
            "--namespace", $Namespace,
            "--query", "registrationState"
        )

        if ($state -eq "Registered") {
            Write-Host "Provider registered: $Namespace"
            return
        }

        Write-Host "Waiting for provider $Namespace registration. Current state: $state"
        Start-Sleep -Seconds 10
    }

    throw "Timed out waiting for Azure provider registration: $Namespace"
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

function Ensure-NsgRule {
    param(
        [Parameter(Mandatory = $true)][string]$RuleName,
        [Parameter(Mandatory = $true)][int]$Priority,
        [Parameter(Mandatory = $true)][string]$SourcePrefix,
        [Parameter(Mandatory = $true)][string]$DestinationPort
    )

    $exists = Test-AzResource @(
        "network", "nsg", "rule", "show",
        "--resource-group", $ResourceGroup,
        "--nsg-name", $cassandraNsgName,
        "--name", $RuleName
    )

    $args = @(
        "network", "nsg", "rule",
        $(if ($exists) { "update" } else { "create" }),
        "--resource-group", $ResourceGroup,
        "--nsg-name", $cassandraNsgName,
        "--name", $RuleName,
        "--priority", "$Priority",
        "--direction", "Inbound",
        "--access", "Allow",
        "--protocol", "Tcp",
        "--source-address-prefixes", $SourcePrefix,
        "--source-port-ranges", "*",
        "--destination-address-prefixes", "*",
        "--destination-port-ranges", $DestinationPort
    )

    Invoke-Az $args
}

function Ensure-PostgresFirewallRule {
    param(
        [Parameter(Mandatory = $true)][string]$RuleName,
        [Parameter(Mandatory = $true)][string]$StartIpAddress,
        [Parameter(Mandatory = $true)][string]$EndIpAddress
    )

    $exists = Test-AzResource @(
        "postgres", "flexible-server", "firewall-rule", "show",
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--rule-name", $RuleName
    )

    $args = @(
        "postgres", "flexible-server", "firewall-rule",
        $(if ($exists) { "update" } else { "create" }),
        "--resource-group", $ResourceGroup,
        "--name", $PostgresServerName,
        "--rule-name", $RuleName,
        "--start-ip-address", $StartIpAddress,
        "--end-ip-address", $EndIpAddress
    )

    Invoke-Az $args
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

function Get-ApiEnvVars {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Api,
        [Parameter(Mandatory = $true)][string]$PostgresFqdn,
        [Parameter(Mandatory = $true)][string]$CassandraPrivateIp
    )

    if ($Api.ContainsKey("DbKind") -and $Api.DbKind -eq "memory") {
        return @(
            "ASPNETCORE_URLS=http://+:8080",
            "SERVICE_KEY=$($Api.Key)",
            "SERVICE_TITLE=$($Api.Title)",
            "DB_KIND=memory",
            "CASSANDRA_HOST=$CassandraPrivateIp",
            "CASSANDRA_PORT=9042"
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
        "DB_PASSWORD=secretref:postgres-password",
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

function Write-PsqlCommands {
    param([Parameter(Mandatory = $true)][string]$PostgresFqdn)

    Write-Host ""
    Write-Host "Optional PostgreSQL schema initialization commands:"
    Write-Host "If running from your workstation, add your client IP to the PostgreSQL firewall first."
    Write-Host "`$env:PGPASSWORD = '<postgres-admin-password>'"

    foreach ($database in $postgresDatabases) {
        $sqlPath = $database.SqlFile.Replace("/", "\")
        Write-Host "psql `"host=$PostgresFqdn port=5432 dbname=$($database.Name) user=$PostgresAdminUser sslmode=require`" -f .\$sqlPath"
    }
}

function Install-Cassandra {
    param(
        [Parameter(Mandatory = $true)][string]$PrivateIp
    )

    if ($SkipCassandraInstall) {
        Write-Host "Skipping Cassandra install because -SkipCassandraInstall was provided."
        return
    }

    $script = @'
#!/usr/bin/env bash
set -eux
export DEBIAN_FRONTEND=noninteractive

sudo apt update
sudo apt install -y ca-certificates curl gnupg apt-transport-https openjdk-17-jre-headless python3

sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://downloads.apache.org/cassandra/KEYS | sudo tee /etc/apt/keyrings/apache-cassandra.asc >/dev/null
sudo chmod 0644 /etc/apt/keyrings/apache-cassandra.asc
echo "deb [signed-by=/etc/apt/keyrings/apache-cassandra.asc] https://debian.cassandra.apache.org 50x main" | sudo tee /etc/apt/sources.list.d/cassandra.sources.list

sudo apt update
sudo apt install -y cassandra

sudo systemctl stop cassandra || true

if [ ! -f /etc/cassandra/cassandra.yaml ]; then
  echo "Missing /etc/cassandra/cassandra.yaml after install" >&2
  exit 1
fi

sudo cp /etc/cassandra/cassandra.yaml /etc/cassandra/cassandra.yaml.bak.$(date +%s)
sudo sed -i "s/^listen_address:.*/listen_address: __PRIVATE_IP__/" /etc/cassandra/cassandra.yaml
sudo sed -i "s/^# *listen_address:.*/listen_address: __PRIVATE_IP__/" /etc/cassandra/cassandra.yaml
sudo sed -i "s/^rpc_address:.*/rpc_address: 0.0.0.0/" /etc/cassandra/cassandra.yaml
sudo sed -i "s/^# *rpc_address:.*/rpc_address: 0.0.0.0/" /etc/cassandra/cassandra.yaml

if grep -Eq '^#?[[:space:]]*broadcast_rpc_address:' /etc/cassandra/cassandra.yaml; then
  sudo sed -i "s/^#*[[:space:]]*broadcast_rpc_address:.*/broadcast_rpc_address: __PRIVATE_IP__/" /etc/cassandra/cassandra.yaml
else
  echo "broadcast_rpc_address: __PRIVATE_IP__" | sudo tee -a /etc/cassandra/cassandra.yaml
fi

if grep -Eq '^[[:space:]]+- seeds:' /etc/cassandra/cassandra.yaml; then
  sudo sed -i 's/^\([[:space:]]*- seeds: \).*/\1"__PRIVATE_IP__"/' /etc/cassandra/cassandra.yaml
fi

if [ -f /etc/cassandra/cassandra-env.sh ]; then
  if grep -Eq '^#?[[:space:]]*MAX_HEAP_SIZE=' /etc/cassandra/cassandra-env.sh; then
    sudo sed -i 's/^#*[[:space:]]*MAX_HEAP_SIZE=.*/MAX_HEAP_SIZE="512M"/' /etc/cassandra/cassandra-env.sh
  else
    echo 'MAX_HEAP_SIZE="512M"' | sudo tee -a /etc/cassandra/cassandra-env.sh
  fi

  if grep -Eq '^#?[[:space:]]*HEAP_NEWSIZE=' /etc/cassandra/cassandra-env.sh; then
    sudo sed -i 's/^#*[[:space:]]*HEAP_NEWSIZE=.*/HEAP_NEWSIZE="128M"/' /etc/cassandra/cassandra-env.sh
  else
    echo 'HEAP_NEWSIZE="128M"' | sudo tee -a /etc/cassandra/cassandra-env.sh
  fi
fi

sudo systemctl daemon-reload
sudo systemctl enable cassandra
sudo systemctl start cassandra || sudo systemctl restart cassandra

for i in $(seq 1 40); do
  if systemctl is-active --quiet cassandra; then
    break
  fi
  sleep 5
done

sudo systemctl status cassandra --no-pager

for i in $(seq 1 60); do
  if nodetool status | tee /tmp/cassandra-nodetool-status.txt && grep -Eq '^UN[[:space:]]' /tmp/cassandra-nodetool-status.txt; then
    exit 0
  fi
  sleep 5
done

echo "Cassandra service started, but nodetool did not report a healthy node in time." >&2
sudo journalctl -u cassandra -n 200 --no-pager || true
sudo tail -n 200 /var/log/cassandra/system.log || true
exit 1
'@

    $script = $script.Replace("__PRIVATE_IP__", $PrivateIp)
    $script = $script -replace "`r`n", "`n"

    $tempScript = [System.IO.Path]::GetTempFileName()
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempScript, $script, $utf8NoBom)
    try {
        Invoke-Az @(
            "vm", "run-command", "invoke",
            "--resource-group", $ResourceGroup,
            "--name", $CassandraVmName,
            "--command-id", "RunShellScript",
            "--scripts", "@$tempScript"
        )
    }
    finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Deploying Azure game architecture"
Write-Host "Resource group: $ResourceGroup"
Write-Host "Container Apps environment: $ContainerAppsEnvironment"
Write-Host "PostgreSQL server: $PostgresServerName"
Write-Host "Cassandra VM: $CassandraVmName"
Write-Host "Mock API image: $mockApiImage"
Write-Host "Gateway image: $gatewayImage"

Invoke-Az @("extension", "add", "--name", "containerapp", "--upgrade")
Wait-AzProvider "Microsoft.App"
Wait-AzProvider "Microsoft.DBforPostgreSQL"
Wait-AzProvider "Microsoft.Compute"
Wait-AzProvider "Microsoft.Network"

Invoke-Az @("group", "create", "--name", $ResourceGroup, "--location", $Location)

$vnetExists = Test-AzResource @("network", "vnet", "show", "--resource-group", $ResourceGroup, "--name", $vnetName)
if ($vnetExists) {
    Write-Host "Reusing VNet: $vnetName"
}
else {
    Invoke-Az @(
        "network", "vnet", "create",
        "--resource-group", $ResourceGroup,
        "--name", $vnetName,
        "--location", $Location,
        "--address-prefixes", "10.42.0.0/16"
    )
}

$containerAppsSubnetExists = Test-AzResource @(
    "network", "vnet", "subnet", "show",
    "--resource-group", $ResourceGroup,
    "--vnet-name", $vnetName,
    "--name", $containerAppsSubnetName
)
if ($containerAppsSubnetExists) {
    Invoke-Az @(
        "network", "vnet", "subnet", "update",
        "--resource-group", $ResourceGroup,
        "--vnet-name", $vnetName,
        "--name", $containerAppsSubnetName,
        "--delegations", "Microsoft.App/environments"
    )
}
else {
    Invoke-Az @(
        "network", "vnet", "subnet", "create",
        "--resource-group", $ResourceGroup,
        "--vnet-name", $vnetName,
        "--name", $containerAppsSubnetName,
        "--address-prefixes", "10.42.0.0/23",
        "--delegations", "Microsoft.App/environments"
    )
}

$cassandraSubnetExists = Test-AzResource @(
    "network", "vnet", "subnet", "show",
    "--resource-group", $ResourceGroup,
    "--vnet-name", $vnetName,
    "--name", $cassandraSubnetName
)
if (-not $cassandraSubnetExists) {
    Invoke-Az @(
        "network", "vnet", "subnet", "create",
        "--resource-group", $ResourceGroup,
        "--vnet-name", $vnetName,
        "--name", $cassandraSubnetName,
        "--address-prefixes", "10.42.2.0/24"
    )
}

if (-not (Test-AzResource @("network", "nsg", "show", "--resource-group", $ResourceGroup, "--name", $cassandraNsgName))) {
    Invoke-Az @("network", "nsg", "create", "--resource-group", $ResourceGroup, "--name", $cassandraNsgName, "--location", $Location)
}

Ensure-NsgRule -RuleName "AllowCassandraFromContainerApps" -Priority 100 -SourcePrefix "10.42.0.0/23" -DestinationPort "9042"
Ensure-NsgRule -RuleName "AllowSshFromVNet" -Priority 110 -SourcePrefix "10.42.0.0/16" -DestinationPort "22"

Invoke-Az @(
    "network", "vnet", "subnet", "update",
    "--resource-group", $ResourceGroup,
    "--vnet-name", $vnetName,
    "--name", $cassandraSubnetName,
    "--network-security-group", $cassandraNsgName
)

$containerAppsSubnetId = Get-AzTsv @(
    "network", "vnet", "subnet", "show",
    "--resource-group", $ResourceGroup,
    "--vnet-name", $vnetName,
    "--name", $containerAppsSubnetName,
    "--query", "id"
)

$envExists = Test-AzResource @(
    "containerapp", "env", "show",
    "--resource-group", $ResourceGroup,
    "--name", $ContainerAppsEnvironment
)
if ($envExists) {
    Write-Host "Reusing Container Apps environment: $ContainerAppsEnvironment"
}
else {
    Invoke-Az @(
        "containerapp", "env", "create",
        "--name", $ContainerAppsEnvironment,
        "--resource-group", $ResourceGroup,
        "--location", $Location,
        "--infrastructure-subnet-resource-id", $containerAppsSubnetId,
        "--logs-destination", "none"
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
}
else {
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
        Invoke-Az @(
            "postgres", "flexible-server", "db", "create",
            "--resource-group", $ResourceGroup,
            "--server-name", $PostgresServerName,
            "--database-name", $database.Name
        )
    }
}

if (-not (Test-AzResource @("network", "nic", "show", "--resource-group", $ResourceGroup, "--name", $cassandraNicName))) {
    Invoke-Az @(
        "network", "nic", "create",
        "--resource-group", $ResourceGroup,
        "--name", $cassandraNicName,
        "--location", $Location,
        "--vnet-name", $vnetName,
        "--subnet", $cassandraSubnetName,
        "--network-security-group", $cassandraNsgName
    )
}

$vmExists = Test-AzResource @("vm", "show", "--resource-group", $ResourceGroup, "--name", $CassandraVmName)
if ($vmExists) {
    Write-Host "Reusing Cassandra VM: $CassandraVmName"
}
else {
    $sshArgs = @()
    if (Test-Path -LiteralPath $SshPublicKeyPath) {
        $sshKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
        $sshArgs = @("--ssh-key-values", $sshKey)
    }
    else {
        $sshArgs = @("--generate-ssh-keys")
    }

    $vmCreateArgs = @(
        "vm", "create",
        "--resource-group", $ResourceGroup,
        "--name", $CassandraVmName,
        "--location", $Location,
        "--image", "Ubuntu2204",
        "--size", $CassandraVmSize,
        "--admin-username", $VmAdminUser,
        "--nics", $cassandraNicName,
        "--authentication-type", "ssh"
    )
    $vmCreateArgs += $sshArgs
    Invoke-Az $vmCreateArgs
}

$cassandraPrivateIp = Get-AzTsv @(
    "network", "nic", "show",
    "--resource-group", $ResourceGroup,
    "--name", $cassandraNicName,
    "--query", "ipConfigurations[0].privateIPAddress"
)

Install-Cassandra -PrivateIp $cassandraPrivateIp

foreach ($api in $apis) {
    $envVars = Get-ApiEnvVars -Api $api -PostgresFqdn $postgresFqdn -CassandraPrivateIp $cassandraPrivateIp
    $secrets = @()

    if (-not ($api.ContainsKey("DbKind") -and $api.DbKind -eq "memory")) {
        $secrets = @("postgres-password=$PostgresAdminPassword")
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
    "--resource-group", $ResourceGroup,
    "--name", "game-api-gateway",
    "--query", "properties.configuration.ingress.fqdn"
)

Write-PsqlCommands -PostgresFqdn $postgresFqdn

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Gateway public URL: https://$gatewayFqdn"
Write-Host "PostgreSQL FQDN: $postgresFqdn"
Write-Host "Cassandra VM private IP: $cassandraPrivateIp"
Write-Host "Cassandra connection string: $($cassandraPrivateIp):9042"
Write-Host ""
Write-Host "Container Apps:"
Write-Host "  game-api-gateway"
foreach ($api in $apis) {
    Write-Host "  $($api.Name)"
}
Write-Host ""
Write-Host "SSH from a host connected to the VNet:"
Write-Host "ssh $VmAdminUser@$cassandraPrivateIp"
Write-Host ""
Write-Host "Cleanup command:"
Write-Host "az group delete -n $ResourceGroup --yes"
