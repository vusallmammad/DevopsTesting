param(
    [int]$DatabaseWaitSeconds = 180,
    [int]$ApiWaitSeconds = 120
)

$ErrorActionPreference = "Stop"

function Invoke-Docker {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Arguments -join ' ')"
    }
}

function Wait-Until {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Probe,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Probe) {
            Write-Host "$Name is ready."
            return
        }

        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Name."
}

function Test-Http {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url
    )

    Wait-Until -Name $Name -TimeoutSeconds $ApiWaitSeconds -Probe {
        try {
            Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 5 | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }

    Write-Host "OK  $Name -> $Url"
}

Write-Host "Starting local Azure-architecture simulation..."
Invoke-Docker @("compose", "up", "-d", "--build")

Wait-Until -Name "PostgreSQL" -TimeoutSeconds $DatabaseWaitSeconds -Probe {
    & docker exec game-postgres pg_isready -U postgres *> $null
    return $LASTEXITCODE -eq 0
}

Wait-Until -Name "Cassandra" -TimeoutSeconds $DatabaseWaitSeconds -Probe {
    & docker exec game-cassandra cqlsh -e "DESCRIBE KEYSPACES;" *> $null
    return $LASTEXITCODE -eq 0
}

Write-Host ""
Write-Host "Running containers:"
Invoke-Docker @("ps")

Write-Host ""
Write-Host "Testing host-exposed health endpoints:"
$healthChecks = @(
    @{ Name = "gateway"; Url = "http://localhost:5000/health" },
    @{ Name = "security-api"; Url = "http://localhost:5015/health" },
    @{ Name = "profile-api"; Url = "http://localhost:5016/health" },
    @{ Name = "tournaments-api"; Url = "http://localhost:5017/health" },
    @{ Name = "teams-api"; Url = "http://localhost:5018/health" },
    @{ Name = "matchup-api"; Url = "http://localhost:5019/health" },
    @{ Name = "store-api"; Url = "http://localhost:5020/health" },
    @{ Name = "game-api"; Url = "http://localhost:5021/health" },
    @{ Name = "notification-api"; Url = "http://localhost:5022/health" }
)

foreach ($check in $healthChecks) {
    Test-Http -Name $check.Name -Url $check.Url
}

Write-Host ""
Write-Host "Testing Docker DNS from api-gateway container..."
$curlCheck = & docker compose exec -T api-gateway sh -c "command -v curl >/dev/null 2>&1" 2>$null
$hasCurl = $LASTEXITCODE -eq 0

if (-not $hasCurl) {
    Write-Host "curl is not installed in the api-gateway image, skipping in-container DNS HTTP checks."
    Write-Host "Gateway-to-service DNS is still configured through *_API_URL environment variables."
}
else {
    $internalUrls = @(
        "http://game-security-api:8080/health",
        "http://game-profile-api:8080/health",
        "http://game-game-api:8080/health",
        "http://game-store-api:8080/health",
        "http://game-teams-api:8080/health",
        "http://game-matchup-api:8080/health",
        "http://game-tournaments-api:8080/health",
        "http://game-notification-api:8080/health"
    )

    foreach ($url in $internalUrls) {
        & docker compose exec -T api-gateway sh -c "curl -fsS '$url' >/dev/null"
        if ($LASTEXITCODE -ne 0) {
            throw "Internal DNS check failed for $url"
        }
        Write-Host "OK  api-gateway -> $url"
    }
}

Write-Host ""
Write-Host "Local simulation is ready."
Write-Host "Gateway: http://localhost:5000"
