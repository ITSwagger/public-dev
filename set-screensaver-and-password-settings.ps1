#Requires -RunAsAdministrator

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    if ($Level -eq "ERROR") {
        Write-Error $Message -ErrorAction SilentlyContinue
    }
}

try {
    $signature = @"
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern bool SystemParametersInfo(int uAction, int uParam, ref int lpvParam, int fuWinIni);
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern bool SystemParametersInfo(int uAction, int uParam, ref bool lpvParam, int fuWinIni);
"@
    $systemParamInfo = Add-Type -MemberDefinition $signature -Name Win32Utils -Namespace SystemUtils -PassThru
}
catch {
    Write-Log -Level ERROR -Message "Failed to compile Win32 API signature. Critical error."
    exit 1
}

function Get-ScreenSaverSetting {
    param([int]$action)
    $value = 0
    try {
        $result = $systemParamInfo::SystemParametersInfo($action, 0, [ref]$value, 0)
        if ($result) {
            return $value
        }
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to get screen saver setting (Action: $action)."
    }
    return $null
}

function Get-ScreenSaverSecure {
    $value = $false
    try {
        $result = $systemParamInfo::SystemParametersInfo(118, 0, [ref]$value, 0) # SPI_GETSCREENSAVERSECURE
        if ($result) {
            return [int]$value
        }
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to get screen saver secure state."
    }
    return $null
}

function Set-ScreenSaverTimeout {
    param ([Int32]$Minutes)
    $desiredSeconds = $Minutes * 60
    $currentSeconds = Get-ScreenSaverSetting -action 14 # SPI_GETSCREENSAVERTIMEOUT
    if ($currentSeconds -ne $desiredSeconds) {
        Write-Log "Setting screen saver timeout to $Minutes minutes."
        $nullVar = 0
        $result = $systemParamInfo::SystemParametersInfo(15, $desiredSeconds, [ref]$nullVar, 2) # SPI_SETSCREENSAVERTIMEOUT
        if (-not $result) {
            Write-Log -Level ERROR "Failed to set screen saver timeout."
        }
    }
    else {
        Write-Log "Screen saver timeout is already set to $Minutes minutes."
    }
}

function Set-OnResumeDisplayLogon {
    param ([int]$Value)
    $currentValue = Get-ScreenSaverSecure
    if ($currentValue -ne $Value) {
        Write-Log "Setting 'On resume, display logon screen' to '$Value'."
        $nullVar = 0
        $result = $systemParamInfo::SystemParametersInfo(119, $Value, [ref]$nullVar, 2) # SPI_SETSCREENSAVERSECURE
        if (-not $result) {
            Write-Log -Level ERROR "Failed to set 'On resume, display logon screen'."
        }
    }
    else {
        Write-Log "'On resume, display logon screen' is already set to '$Value'."
    }
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $DesiredValue
    )
    try {
        $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
        if ($currentValue -ne $DesiredValue) {
            Write-Log "Setting registry value '$Name' at '$Path'."
            Set-ItemProperty -Path $Path -Name $Name -Value $DesiredValue
        }
        else {
            Write-Log "Registry value '$Name' at '$Path' is already correctly set."
        }
    }
    catch {
        Write-Log "Setting registry value '$Name' at '$Path' (value did not exist)."
        Set-ItemProperty -Path $Path -Name $Name -Value $DesiredValue
    }
}

function Set-NetAccountPolicy {
    param(
        [string]$Policy,
        [int]$DesiredValue
    )
    try {
        $netAccounts = net accounts
        $currentValue = ($netAccounts | Select-String -Pattern "$Policy\s+(\d+|NEVER)") -replace '\s+', ' ' -split ' ' | Select-Object -Last 1
        if ($currentValue -eq "NEVER") { $currentValue = 4294967295 }

        if ([int]$currentValue -ne $DesiredValue) {
            Write-Log "Setting Net Account Policy '$Policy' to '$DesiredValue'."
            net accounts /$($Policy.Replace(' ','')):$DesiredValue
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level ERROR "Failed to set '$Policy'."
            }
        }
        else {
            Write-Log "Net Account Policy '$Policy' is already set to '$DesiredValue'."
        }
    }
    catch {
        Write-Log -Level ERROR "Could not parse or set '$Policy'."
    }
}

function Set-AuditPolicy {
    param(
        [string]$Category
    )
    try {
        $auditState = (auditpol /get /category:"$Category" | Select-String "Success and Failure")
        if (-not $auditState) {
            Write-Log "Enabling Success and Failure auditing for '$Category'."
            auditpol /set /category:"$Category" /success:enable /failure:enable
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level ERROR "Failed to set audit policy for '$Category'."
            }
        }
        else {
            Write-Log "Auditing for '$Category' is already enabled for Success and Failure."
        }
    }
    catch {
        Write-Log -Level ERROR "Could not parse or set audit policy for '$Category'."
    }
}

function Set-PasswordComplexity {
    $tempFile = Join-Path $env:TEMP "CurrentSec.inf"
    try {
        secedit /export /cfg $tempFile /quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to export security policy."
        }

        $content = Get-Content $tempFile
        $complexityLine = $content | Select-String "PasswordComplexity"
        
        if ($complexityLine -notmatch "PasswordComplexity = 1") {
            Write-Log "Setting Password Complexity to enabled."
            $newContent = $content -replace "PasswordComplexity = 0", "PasswordComplexity = 1"
            $newContent | Out-File $tempFile -Encoding "unicode"
            
            $sdbPath = Join-Path $env:windir "security\database\custom.sdb"
            secedit /configure /db $sdbPath /cfg $tempFile /areas SECURITYPOLICY /quiet
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to configure security policy."
            }
            gpupdate /force
        }
        else {
            Write-Log "Password Complexity is already enabled."
        }
    }
    catch {
        Write-Log -Level ERROR -Message "An error occurred while setting password complexity: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

Write-Log "--- Starting System Hardening Script ---"

Write-Log "--- Configuring Screen Saver Settings ---"
Set-ScreenSaverTimeout -Minutes 15
Set-OnResumeDisplayLogon -Value 1
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -DesiredValue "1"
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "scrnsave.exe" -DesiredValue "C:\Windows\System32\scrnsave.scr"

Write-Log "--- Configuring Password and Account Policies ---"
Set-NetAccountPolicy -Policy "Minimum password length" -DesiredValue 8
Set-NetAccountPolicy -Policy "Maximum password age (days)" -DesiredValue 60
Set-NetAccountPolicy -Policy "Minimum password age (days)" -DesiredValue 0
Set-NetAccountPolicy -Policy "Length of password history maintained" -DesiredValue 8
Set-NetAccountPolicy -Policy "Lockout duration (minutes)" -DesiredValue 30
Set-NetAccountPolicy -Policy "Lockout observation window (minutes)" -DesiredValue 30
Set-NetAccountPolicy -Policy "Lockout threshold" -DesiredValue 5

Write-Log "--- Configuring Audit Policies ---"
Set-AuditPolicy -Category "Account Logon"
Set-AuditPolicy -Category "Account Management"
Set-AuditPolicy -Category "Logon/Logoff"

Write-Log "--- Configuring Password Complexity ---"
Set-PasswordComplexity

Write-Log "--- System Hardening Script Finished ---"
