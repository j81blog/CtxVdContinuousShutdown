<#
.NAME
	CtxVdContinuousShutdown
.SYNOPSIS  
	Continuous cheching for old XenDesktop VM's and shutting some of them down.
.DESCRIPTION  
	Continuous cheching for old XenDesktop VM's and shutting some of them down.
	Required: Powershell v3
.NOTES  
	File Name  : CtxVdContinuousShutdown.ps1
	Author     : John Billekens - john@j81.nl
	Requires   : Citrix Delivery Controller 7.x
	Version    : 20151112.2123
.SYNTAX
	.\CtxVdContinuousShutdown.ps1 [-MaxShutdowns <number>] [-DesktopGroupName <string>] [-EnableLogging] [-LogDir <string>] [-LogFile <string>] [-EnableLoggingOnly]
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -MaxShutdowns 20 -EnableLogging -LogFile "Log.txt"
	
	Rebooting 20 old VM's while logging to .\Log.txt
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -MaxShutdowns 25 -DesktopGroupName "Production" -EnableLogging -LogDir "C:\Temp"
	
	Rebooting 25 old VM's from the Production Delivery Group while logging to C:\Temp\CtxVdContinuousShutdown.txt
.EXAMPLE
	.\CtxVdContinuousShutdown.ps1 -EnableLogging
	
	Rebooting 15 (default) old VM's from every Delivery Group while logging to C:\Temp\logfile.txt
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
	Activates writing to a log file, the option -LogDir add/or -LogFile can be used to specify location.
	
	.\CtxVdContinuousShutdown.ps1 -EnableLogging
	Default: False
.PARAMETER EnableLoggingOnly
	Activates writing to a log file only, no power actions will be executed. -EnableLogging not necessary.
	The option -LogDir add/or -LogFile can be used to specify location. 
	
	.\CtxVdContinuousShutdown.ps1 -EnableLoggingOnly
	Default: False
.PARAMETER LogDir
	Specify log path.
	Note: also specify -EnableLogging to log data to file.
	
	.\CtxVdContinuousShutdown.ps1 -LogDir "C:\Temp"
	Default: <current path>\
.PARAMETER LogFile
	Specify log filename.
	Note: also specify -EnableLogging to log data to file.
	
	.\CtxVdContinuousShutdown.ps1 -LogFile "logfile.txt"
	Default: <current path>\CtxVdContinuousShutdown.txt
#>

[cmdletbinding()]
Param(
	[Parameter(Mandatory=$false)][int32]$MaxShutdowns = 15,
	[Parameter(Mandatory=$false)][string]$DesktopGroupName = "*",
	[Parameter(Mandatory=$false)][switch]$EnableLoggingOnly = $false,
	[Parameter(Mandatory=$false)][switch]$EnableLogging = $false,
	[Parameter(Mandatory=$false)][string]$LogDir = ".",
	[Parameter(Mandatory=$false)][string]$LogFile = "CtxVdContinuousShutdown.txt" 
	
)

$PowerShellVersion = (Get-Host | Select-Object Version).Version.Major
If (!($PowerShellVersion -ge 7 )) {
	Write-Host -ForegroundColor Yellow "Please use at least PowerShell version 3"
	Write-Host -ForegroundColor Yellow "Current Version:" $PowerShellVersion
	Break
}

IF (-not (Get-Module -Name Citrix.*)) {
	Import-Module Citrix.*
}
IF (-not (Get-PSSnapin -Name Citrix.* -ErrorAction SilentlyContinue)) {
	Add-PSSnapin Citrix.*
}
$id = get-date -format 'HHmm'
$Log = $LogDir.Trimend('\') + "\" + $LogFile

If ($EnableLoggingOnly){ 
	$EnableLogging = $true
	$id = ($id + "-LogOnly ")
}
function ToLog ([string]$LogText) {
	If ($EnableLogging){
		$date = get-date -format 'yyyy-MM-dd HH:mm:ss'
		Write-Output  "$date - $id | $LogText" | Out-File $Log -width 240 -Append
	}
}

$machines = @()
ToLog ("***************************************************************")
ToLog ("Start Collecting old VM's")
$Objects = Get-BrokerHostingPowerAction -Filter {ActionCompletionTime -lt "-20:00" -and ((Action -eq "TurnOn") -or (Action -eq "Restart") -or (Action -eq "Reset"))}  -MaxRecordCount 5000
ForEach ($Object in $Objects) {
	$machine = $null
	$BrokerMachine = Get-BrokerMachine -MachineName $Object.MachineName
	If (($BrokerMachine.SessionCount -eq 0) -and ($BrokerMachine.RegistrationState -eq "Registered") -and ($BrokerMachine.PowerState -eq "On")) {
		$machine = New-Object System.Object
		$machine | Add-Member -type NoteProperty -name ActionCompletionTime -value $Object.ActionCompletionTime
		$machine | Add-Member -type NoteProperty -name MachineName -value $Object.MachineName
		$machine | Add-Member -type NoteProperty -name DesktopGroupName -value $BrokerMachine.DesktopGroupName
		$machine | Add-Member -type NoteProperty -name HostedMachineName -value $BrokerMachine.HostedMachineName
		$machine | Add-Member -type NoteProperty -name LastAction -value "None"
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
	If (($machine.SessionCount -eq "0") -and ($machine.SessionsEstablished -eq "0") -and ($machine.SessionsPending -eq "0")) {
		ToLog ($machines[$i].HostedMachineName + ", " + $machines[$i].ActionCompletionTime)
		If (!($EnableLoggingOnly)) { 
			Set-BrokerMachine -MachineName $machines[$i].MachineName -InMaintenanceMode $true
			$machines[$i].LastAction = "MaintenanceMode"
			ToLog ("Set Action: " + $machines[$i].LastAction)
		}
		If (!($EnableLoggingOnly)) { 
			New-BrokerHostingPowerAction -MachineName $machines[$i].MachineName -Action "Shutdown" | Out-Null
			$machines[$i].LastAction = "Shutdown"
			ToLog ("Set Action: " + $machines[$i].LastAction)
		}
	}
}
$machines = $machines  | Where {$_.LastAction -like "Shutdown"}
$machine = $null
$final = 0
If ($EnableLoggingOnly) {
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
		If ((Get-BrokerMachine -MachineName $machines[$i].MachineName).PowerState -eq "Off") {
			If (!($EnableLoggingOnly)) { 
				Set-BrokerMachine -MachineName $machines[$i].MachineName -InMaintenanceMode $false
				$machines[$i].LastAction = "Done"
				ToLog ($machines[$i].HostedMachineName + ", out maintenance mode.")
			}
		}
	}
	$machines = $machines | Where {$_.LastAction -like "Shutdown"}
	If ($machines.length -eq 0) {
		break
	} else {
		If (!($EnableLoggingOnly)) {
			ToLog ("Waiting 30s for machines to shutdown. " + [string]$machines.length + " to go")
			Start-Sleep -s 30
		}
	}
}
ToLog ("Finished!")
ToLog ("***************************************************************")

$MaxLines = 5000
If (Test-Path $Log) {
	(get-content $Log -tail $MaxLines -readcount 0 -Encoding Unicode) | set-content $Log -Encoding Unicode
}
