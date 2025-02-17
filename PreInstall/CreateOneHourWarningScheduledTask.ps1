﻿# Self-elevate the script if required
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
  if ([int](Get-CimInstance -class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
    $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
    Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
    exit
  }
}

Write-Host "This script sets your machine to warn you 5 minutes before your machine bills you for an hour,
This is useful if your Machine bills per hour, like AWS"

$confirmation = Read-Host "Are you Sure You Want To Proceed: Y/N"
switch ($confirmation) {
  Y {
  }
  N {
    exit
  }
}


try {
  Get-ScheduledTask -TaskName "One Hour Warning Message" -ErrorAction Stop | Out-Null
  $ModifyOrRemove = "You already have the script installed, remove it?"
  switch ($ModifyOrRemove) {
    N {
    }
    Y {
      Unregister-ScheduledTask -TaskName "One Hour Warning Message" -Confirm:$false
      "The warning message has been removed"
      Pause
      exit }
  }
}
catch {
}



try {
  Get-ScheduledTask -TaskName "One Hour Warning Message" -ErrorAction Stop | Out-Null
  Unregister-ScheduledTask -TaskName "One Hour Warning Message" -Confirm:$false
}
catch {
}

$action = New-ScheduledTaskAction -Execute 'C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe' -argument '-executionpolicy bypass -windowstyle hidden -file %programdata%\ParsecLoader\WarningMessage.ps1'

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "One Hour Warning Message" -Description "This will warn you 5 minutes before you're billed for another hour" -RunLevel Highest

Write-Output "Successfully Created"

Pause
