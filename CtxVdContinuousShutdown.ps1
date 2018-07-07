<#
.SYNOPSIS  
	Continuous checking for old XenDesktop VM's and shutting some of them down.
.DESCRIPTION  
	Continuous checking for old XenDesktop VM's and shutting some of them down.
	Required: Powershell v3
.PARAMETER MaxShutdowns
	Specify the maximum of simultanious shutdowns when running this script.
	Only enter a full integer number.

	.\CtxVdContinuousShutdown.ps1 -MaxShutdowns 30
	Default: 15
.PARAMETER DesktopGroupName
	Specify the XenDesktop Delivery Group name to check against
	
	.\CtxVdContinuousShutdown.ps1 -DesktopGroupName "Production"
	Default: Everything (*)
.PARAMETER EnableLogging
	Activates writing to a log file, the option -LogPath add/or -LogFile can be used to specify location.
	
	.\CtxVdContinuousShutdown.ps1 -EnableLogging
	Default: False
.PARAMETER EnableLoggingOnly
	Activates writing to a log file only, no power actions will be executed. -EnableLogging not necessary.
	The option -LogPath add/or -LogFile can be used to specify location. 
	
	.\CtxVdContinuousShutdown.ps1 -EnableLoggingOnly
	Default: False
.PARAMETER LogPath
	Specify log path.
	Note: also specify -EnableLogging to log data to file.
	
	.\CtxVdContinuousShutdown.ps1 -LogPath "C:\Temp"
	Default: <current path>\
.PARAMETER LogFile
	Specify log filename.
	Note: also specify -EnableLogging to log data to file.
	
	.\CtxVdContinuousShutdown.ps1 -LogFile "logfile.txt"
	Default: <current path>\CtxVdContinuousShutdown.txt
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -MaxShutdowns 20 -EnableLogging -LogFile "Log.txt"
	
	Rebooting 20 old VM's while logging to .\Log.txt
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -MaxShutdowns 25 -DesktopGroupName "Production" -EnableLogging -LogPath "C:\Temp"
	
	Rebooting 25 old VM's from the Production Delivery Group while logging to C:\Temp\CtxVdContinuousShutdown.txt
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -EnableLogging
	
	Shutting down 15 (default) old VM's from every Delivery Group while logging to C:\Temp\logfile.txt
.NOTES  
	File Name  : CtxVdContinuousShutdown.ps1
	Author     : John Billekens - john@j81.nl
	Requires   : Citrix Delivery Controller 7.x
	Version    : 20151112.2123
.LINK
	https://blog.j81.nl
#>

[cmdletbinding()]
Param(
	[Parameter(Mandatory=$false)][int32]$MaxShutdowns = 15,
	[Parameter(Mandatory=$false)][string]$DesktopGroupName = "*",
	[Parameter(Mandatory=$false)][switch]$EnableLoggingOnly = $false,
	[Parameter(Mandatory=$false)][switch]$EnableLogging = $false,
	[Parameter(Mandatory=$false)][alias("LogDir")][string]$LogPath = ".",
	[Parameter(Mandatory=$false)][string]$LogFile = "CtxVdContinuousShutdown.txt" 
	[Parameter(Mandatory=$false)][string]$JobFile = "$(Join-Path $($env:temp) 'jobdata.xml')" 
	
)

$PowerShellVersion = (Get-Host | Select-Object Version).Version.Major
if (!($PowerShellVersion -ge 7 )) {
	Write-Host -ForegroundColor Yellow "Please use at least PowerShell version 3"
	Write-Host -ForegroundColor Yellow "Current Version:" $PowerShellVersion
	Break
}

if (-not (Get-Module -Name Citrix.*)) {
	Import-Module Citrix.*
}
if (-not (Get-PSSnapin -Name Citrix.* -ErrorAction SilentlyContinue)) {
	Add-PSSnapin Citrix.*
}
$id = get-date -format 'HHmm'
$PathFileLog= Join-Path $LogPath $LogFile

if ($EnableLoggingOnly){ 
	$EnableLogging = $true
	$id = ($id + "-LogOnly ")
}
function ToLog ([string]$LogText) {
	if ($EnableLogging){
		$date = get-date -format 'yyyy-MM-dd HH:mm:ss'
		Write-Output  "$date - $id | $LogText" | Out-File $PathFileLog -width 240 -Append
	}
}

$machines = @()
ToLog ("***************************************************************")
ToLog ("Start Collecting old VM's")
$Objects = Get-BrokerHostingPowerAction -Filter {ActionCompletionTime -lt "-20:00" -and ((Action -eq "TurnOn") -or (Action -eq "Restart") -or (Action -eq "Reset"))}  -MaxRecordCount 5000
ForEach ($Object in $Objects) {
	$machine = @()
	$BrokerMachine = Get-BrokerMachine -MachineName $Object.MachineName
	if (($BrokerMachine.SessionCount -eq 0) -and ($BrokerMachine.RegistrationState -eq "Registered") -and ($BrokerMachine.PowerState -eq "On")) {
		$machine = = [PSCustomObject]@{
			ActionCompletionTime = $Object.ActionCompletionTime
			MachineName = $Object.MachineName
			DesktopGroupName = $BrokerMachine.DesktopGroupName
			HostedMachineName = $BrokerMachine.HostedMachineName
			LastAction = "None"
		}
		$machines += $machine
	}
}
$machines = $machines  | Where{$_.DesktopGroupName -like $DesktopGroupName} | Sort-Object ActionCompletionTime 
ToLog ("Done, found " + [string]$machines.length + " old machines. Only shutting " + [string]$MaxShutdowns + " down this round")
$machine = $null
for ($i=0; $i -lt $machines.length; $i++) {
	if ($i -eq $MaxShutdowns){
		ToLog ("Max shutdowns reached.")
		break
	}
	$machine = Get-BrokerMachine -MachineName $machines[$i].MachineName
	if (($machine.SessionCount -eq "0") -and ($machine.SessionsEstablished -eq "0") -and ($machine.SessionsPending -eq "0")) {
		ToLog ($machines[$i].HostedMachineName + ", " + $machines[$i].ActionCompletionTime)
		if (!($EnableLoggingOnly)) { 
			Set-BrokerMachine -MachineName $machines[$i].MachineName -InMaintenanceMode $true
			$machines[$i].LastAction = "MaintenanceMode"
			ToLog ("Set Action: " + $machines[$i].LastAction)
		}
		if (!($EnableLoggingOnly)) { 
			New-BrokerHostingPowerAction -MachineName $machines[$i].MachineName -Action "Shutdown" | Out-Null
			$machines[$i].LastAction = "Shutdown"
			ToLog ("Set Action: " + $machines[$i].LastAction)
		}
	}
}
$machines = $machines  | Where {$_.LastAction -like "Shutdown"}
$machine = $null
$final = 0
if ($EnableLoggingOnly) {
	$finalloop = 1
} else {
	ToLog ("Waiting 30s for machines to shutdown.")
	$finalloop = 10
	Start-Sleep -s 30
}

While ($final -ne $finalloop) {
	$final++
	ToLog ([string]$machines.length + " machines to check, round " + [string]$final + "")
	for ($i=0; $i -lt $machines.length; $i++) {
		if ((Get-BrokerMachine -MachineName $machines[$i].MachineName).PowerState -eq "Off") {
			if (!($EnableLoggingOnly)) { 
				Set-BrokerMachine -MachineName $machines[$i].MachineName -InMaintenanceMode $false
				$machines[$i].LastAction = "Done"
				ToLog ($machines[$i].HostedMachineName + ", out maintenance mode.")
			}
		}
	}
	$machines = $machines | Where {$_.LastAction -like "Shutdown"}
	if ($machines.length -eq 0) {
		break
	} else {
		if (!($EnableLoggingOnly)) {
			ToLog ("Waiting 30s for machines to shutdown. " + [string]$machines.length + " to go")
			Start-Sleep -s 30
		}
	}
}
ToLog ("Finished!")
ToLog ("***************************************************************")

$MaxLines = 5000
if (Test-Path $PathFileLog) {
	(get-content $PathFileLog -tail $MaxLines -readcount 0 -Encoding Unicode) | set-content $PathFileLog -Encoding Unicode
}
