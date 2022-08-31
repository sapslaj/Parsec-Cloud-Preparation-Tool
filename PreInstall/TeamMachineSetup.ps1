[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Security

$MeEndpoint = "https://kessel-api.parsecgaming.com/me"
$userBinPath = "C:\ProgramData\Parsec\user.bin"
$configtxtdir = 'C:\ProgramData\Parsec\config.txt'

class Post
{
  [string]$name
  [string]$peer_id
  [int]$team_group_id
  [int]$user_id
  [string]$user_email
  [string]$key
  [string]$team_id
  [bool]$is_guest_access = $false

  [void] Fill () {
    $config = fetchUserData
    foreach ($line in $config) {
      $this. "$($line.split("=")[0])" = $($line.Split("=")[1])
      $this.peer_id = $(PeerIDGetter)
      if (!$this.Name) { $this.Name = $env:COMPUTERNAME }
    }
  }
}


function fetchUserData {
  $metadata = $(
    try {
      (Invoke-WebRequest -Uri http://metadata.google.internal/computeMetadata/v1/instance/attributes/parsec -Method GET -Header @{ 'metadata-flavor' = 'Google' } -TimeoutSec 5)
      $stream = "bytes"
    }
    catch {
    }
    try {
      (Invoke-WebRequest -Uri http://metadata.paperspace.com/meta-data/machine -TimeoutSec 5)
      $stream = "bytes"
    }
    catch {
    }
    try {
      (Invoke-WebRequest -Uri "http://169.254.169.254/latest/user-data?" -TimeoutSec 5)
      $stream = "bytes"
    }
    catch {
    }
    try {
      Invoke-WebRequest -Headers @{ "Metadata" = "true" } -Uri "http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text" -TimeoutSec 5
      $stream = "base64"
    }
    catch {
    }
  )
  if ($metadata.StatusCode -eq 200) {
    if (($metadata.Content.Length) -gt 1) {
      if ($stream -eq "bytes") {
        [System.Text.Encoding]::ASCII.GetString($metadata.Content).Split(':')
      }
      elseif ($stream -eq "base64") {
        [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($metadata.Content)).Split(':')
      }
    }
    else {
      #no userdata found, exiting...
      exit
    }
  }
  else {
    #no userdata found, exiting...
    exit
  }
}


function PeerIDGetter {
  $configfile = Get-Content $configtxtdir
  foreach ($configline in $configfile) {
    if ($configline -like 'app_host_peer_id*') {
      $peerid = $configline.Split(' = ')[-1]
    }
  }
  if ($peerid -eq $NULL) { $peerid = $NULL }
  return $peerid
}


function WritePeerID {
  param(
    $peer_id
  )
  $configfile = Get-Content $configtxtdir
  $File = foreach ($configline in $configfile) {
    if ($configline -like 'app_host_peer_id*') {
    }
    else { $configline }
  }
  $file += "app_host_peer_id=$peer_id"
  $file | Out-File $configtxtdir -Encoding ascii
}

function WriteHostname {
  param(
    $host_name
  )
  $configfile = Get-Content $configtxtdir
  $File = foreach ($configline in $configfile) {
    if ($configline -like 'host_name*') {
    }
    else { $configline }
  }
  $file += "host_name=$host_name"
  $file | Out-File $configtxtdir -Encoding ascii
}


function SessionIDFromUserBin {
  if (Test-Path $userBinPath) {
    Add-Type -AssemblyName System.Security
    $scope = [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    [byte[]]$binbyte = Get-Content $userBinPath -Encoding byte
    $decryptuserBin = [System.Security.Cryptography.ProtectedData]::Unprotect($binbyte,$null,$scope)
    $parseuserbin = [System.Text.Encoding]::ASCII.GetString($decryptuserBin)
    return $parseuserbin.Split('"')[-2]
  }
  else {
    return 0
  }
}

function SessionIDToUserBin {
  param(
    [string]$session
  )
  $userBinJson = @{
    "session_id" = $session
  } | ConvertTo-Json
  $scope = [System.Security.Cryptography.DataProtectionScope]::LocalMachine
  $input = [System.Text.UTF8Encoding]::UTF8.GetBytes($userBinJson)
  $userBin = [System.Security.Cryptography.ProtectedData]::Protect($input,$null,$scope)
  Set-Content $userBinPath -Value $userBin -Encoding Byte
}


function PostTeamEndpoint {
  param(
    [post]$Params
  )
  $body = $Params | Select-Object * -ExcludeProperty key,team_id
  $TeamEndpointHeaders = @{
    "Content-Type" = "application/json"
    "X-Machine-Key" = $params.key
  }
  $TeamEndpointRequest = Invoke-RestMethod -Uri $TeamEndoint -Method POST -Headers $TeamEndpointHeaders -Body ($body | ConvertTo-Json)
  return $TeamEndpointRequest
}


function GenerateMeData {
  param(
    [string]$Session
  )
  $SessionHeader = @{
    "Authorization" = "Bearer $Session"
  }
  $array = (Invoke-RestMethod -Uri $MeEndpoint -Method GET -Headers $SessionHeader).data
  $array
}


$RequestDetails = [Post]::new()
$RequestDetails.Fill()
$TeamEndoint = "https://kessel-api.parsecgaming.com/teams/{0}/machines" -f $RequestDetails.team_id
$TeamsEndpointRequest = PostTeamEndpoint -params $RequestDetails
WritePeerID -peer_id $TeamsEndpointRequest.data.host_peer_id
WriteHostname -host_name $RequestDetails.Name
#$Details = GenerateMeData -Session $TeamsEndpointRequest.data.id
SessionIDToUserBin -Session $TeamsEndpointRequest.data.id

Stop-Process -Name parsecd -Force
