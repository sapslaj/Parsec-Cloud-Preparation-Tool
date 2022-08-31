
$CountSinceStart = 0
function CountSinceStart { $MinutesSinceStart = [int]3240 - $($(Get-Date) - $(Get-EventLog -LogName System -InstanceId 12 -Newest 1).TimeGenerated).TotalSeconds
  if ($MinutesSinceStart -lt 0) {
    $MinutesSinceStart = 0 }
  else {}

  do {
    $CountSinceStart++
    Start-Sleep -s 1
  }
  until
  (
    $CountSinceStart -ge $MinutesSinceStart
  )
  Start-Process powershell.exe -ArgumentList "-windowstyle hidden -executionpolicy bypass -file $env:programdata\ParsecLoader\ShowDialog.ps1"
}


CountSinceStart
