#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [int]$MinDownloadSpeedMbps = 20,

    [Parameter(Mandatory = $false)]
    [string]$DownloadUrl = "http://speedtest-tele2.net/10MB.zip",

    [Parameter(Mandatory = $false)]
    [int]$FileSizeMB = 10
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    if ($Level -in @("ERROR", "FAIL")) {
        Write-Error $Message -ErrorAction SilentlyContinue
    }
}

$localFile = Join-Path $env:TEMP "speedtest_$(Get-Random).tmp"
$webClient = New-Object System.Net.WebClient
$exitCode = 1 # Default to failure

try {
    Write-Log "Starting network download speed test."
    Write-Log "Minimum acceptable speed: $MinDownloadSpeedMbps Mbps."
    Write-Log "Downloading $FileSizeMB MB file from $DownloadUrl"

    $downloadTime = Measure-Command {
        $webClient.DownloadFile($DownloadUrl, $localFile)
    }
    
    $secondsTaken = $downloadTime.TotalSeconds
    if ($secondsTaken -lt 0.1) {
        Write-Log -Level "WARN" -Message "Download completed too quickly ($([math]::Round($secondsTaken, 4))s) to ensure an accurate measurement."
        $exitCode = 0
        return
    }

    $downloadSpeed = [math]::Round((($FileSizeMB * 8) / $secondsTaken), 2)

    Write-Log "Download completed in $([math]::Round($secondsTaken, 2)) seconds."
    
    if ($downloadSpeed -ge $MinDownloadSpeedMbps) {
        Write-Log -Level "PASS" -Message "Speed is acceptable. Current download speed is $downloadSpeed Mbps."
        $exitCode = 0
    }
    else {
        Write-Log -Level "FAIL" -Message "Speed is UNACCEPTABLE. Current download speed of $downloadSpeed Mbps is below the minimum threshold of $MinDownloadSpeedMbps Mbps."
        $exitCode = 1
    }
}
catch {
    Write-Log -Level "ERROR" -Message "A critical error occurred during the speed test: $($_.Exception.Message)"
    $exitCode = 1
}
finally {
    if (Test-Path $localFile) {
        Remove-Item $localFile -Force -ErrorAction SilentlyContinue
    }
    if ($webClient) {
        $webClient.Dispose()
    }
    Write-Log "Speed test finished."
    exit $exitCode
}
