####################################
#SCREEN SAVER SETTINGS
####################################
$signature = @"
[DllImport("user32.dll")]
public static extern bool SystemParametersInfo(int uAction, int uParam, ref int lpvParam, int flags );
"@
$systemParamInfo = Add-Type -memberDefinition  $signature -Name ScreenSaver -passThru

Function Get-ScreenSaverTimeout
{
  [Int32]$value = 15
  $systemParamInfo::SystemParametersInfo(14, 0, [REF]$value, 0)
  $($value/60)
}

Function Set-ScreenSaverTimeout
{
  Param ([Int32]$value)
  $seconds = $value * 60
  [Int32]$nullVar = 0
  $systemParamInfo::SystemParametersInfo(15, $seconds, [REF]$nullVar, 2)
}

Function Set-OnResumeDisplayLogon
{
    Param ([Int32]$value)
    [Int32]$nullVar = 0
    $systemParamInfo::SystemParametersInfo(119, $value, [REF]$nullVar, 2)
}
Set-OnResumeDisplayLogon(1)
Set-ScreenSaverTimeout(20)
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name ScreenSaveActive -Value 1
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name scrnsave.exe -Value "C:\Windows\System32\scrnsave.scr"

####################################
#SET PASSWORD SETTINGS
####################################
net accounts /uniquepw:8
net accounts /maxpwage:60
net accounts /minpwage:0
net accounts /minpwlen:8
net accounts /lockoutwindow:30
net accounts /lockoutduration:30
net accounts /lockoutthreshold:5
Auditpol /set /category:"Account Logon" /Success:enable /failure:enable
Auditpol /set /category:"Account Management" /Success:enable /failure:enable
Auditpol /set /category:"Logon/Logoff" /Success:enable /failure:enable

####################################
#SET PASSWORD COMPLEXITY
####################################
secedit /export /cfg c:\CurrentSec.txt
(gc c:\CurrentSec.txt) -replace("PasswordComplexity = 0", "PasswordComplexity = 1") | out-file c:\CurrentSec.txt
secedit /configure /db C:\windows\security\database\mycustomsecdb.sdb /cfg c:\CurrentSec.txt /areas SECURITYPOLICY
gpupdate
rm -force c:\CurrentSec.txt -confirm:$false
