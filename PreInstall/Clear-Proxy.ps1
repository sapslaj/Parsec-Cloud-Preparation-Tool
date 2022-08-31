#clear windows proxy

$size = (Get-PartitionSupportedSize -DiskNumber 0 -PartitionNumber 1)
[System.UInt64]$currentsize = (Get-Partition -DiskNumber 0 -PartitionNumber 1).Size
[System.UInt64]$maxpartitionsize = ($size.SizeMax).ToString()

if ($($currentsize) -ge $($maxpartitionsize)) {
  "Hard Drive already expanded"
}
else
{
  Resize-Partition -DiskNumber 0 -PartitionNumber 1 -Size $size.SizeMax
  "Successfully Increased Partition Size"
}


function clear-proxy {
  $value = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable
  if ($value.ProxyEnable -eq 1) {
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyEnable -Value 0 | Out-Null
    Write-Host "Disable proxy if required"
    Start-Process "C:\Program Files\Internet Explorer\iexplore.exe"
    Start-Sleep -s 5
    Get-Process iexplore | ForEach-Object { $_.CloseMainWindow() | Out-Null } | Stop-Process –force }
  else {} }

#fix gpu

function EnableDisabledGPU {
  $getdisabled = Get-WMIObject win32_pnpentity | Where-Object { $_.Name -like '*NVIDIA*' -or $_.Name -like '3D Video Controller' -and $_.status -like 'Error' } | Select-Object -ExpandProperty PNPDeviceID
  if ($getdisabled -ne $null) { "Enabling GPU"
    $var = $getdisabled.substring(0,21)
    $arguement = "/r enable" + ' ' + "*" + "$var" + "*"
    Start-Process -FilePath "C:\ParsecTemp\Devcon\devcon.exe" -ArgumentList $arguement
  }
  else { "Device is enabled"
    Start-Process -FilePath "C:\ParsecTemp\Devcon\devcon.exe" -ArgumentList '/m /r' }
}



function installedGPUID {
  #queries WMI to get DeviceID of the installed NVIDIA GPU
  try { (Get-WMIObject -query "select DeviceID from Win32_PNPEntity Where (deviceid Like '%PCI\\VEN_10DE%') and (PNPClass = 'Display' or Name = '3D Video Controller')" | Select-Object DeviceID -ExpandProperty DeviceID).substring(13,8) }
  catch { return $null }
}

function driverVersion {
  #Queries WMI to request the driver version, and formats it to match that of a NVIDIA Driver version number (NNN.NN)
  try { (Get-WMIObject Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like "*nvidia*" -and $_.DeviceClass -like "Display" } | Select-Object -ExpandProperty DriverVersion).substring(7,6).Replace('.','').Insert(3,'.') }
  catch { return $null }
}

function osVersion {
  #Requests Windows OS Friendly Name
  (Get-WMIObject -class Win32_OperatingSystem).Caption
}

function requiresReboot {
  #Queries if system needs a reboot after driver installs
  if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { return $true }
  if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { return $true }
  if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { return $true }
  try {
    $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
    $status = $util.DetermineIfRebootPending()
    if (($status -ne $null) -and $status.RebootPending) {
      return $true
    }
  } catch {}

  return $false
}

function validDriver {
  #checks an important nvidia driver folder to see if it exits
  Test-Path -Path "C:\Program Files\NVIDIA Corporation\NVSMI"
}

function webDriver {
  #checks the latest available graphics driver from nvidia.com
  if (($gpu.supported -eq "No") -eq $true) { "Sorry, this GPU (" + $gpu.Name + ") is not yet supported by this tool."
    exit
  }
  elseif (($gpu.supported -eq "UnOfficial") -eq $true) {
    if ($url.GoogleGRID -eq $null) { $URL.GoogleGRID = Invoke-WebRequest -Uri https://cloud.google.com/compute/docs/gpus/add-gpus#installing_grid_drivers_for_virtual_workstations -UseBasicParsing } else {}
    $($($URL.GoogleGRID).Links | Where-Object href -Like *server2016_64bit_international.exe*).outerHTML.Split('/')[6].Split('_')[0]
  }
  else {
    $gpu.URL = "https://www.nvidia.com/Download/processFind.aspx?psid=" + $gpu.psid + "&pfid=" + $gpu.pfid + "&osid=" + $gpu.osid + "&lid=1&whql=1&lang=en-us&ctk=0"
    $link = Invoke-WebRequest -Uri $gpu.URL -Method GET -UseBasicParsing
    $link -match '<td class="gridItem">([^<]+?)</td>' | Out-Null
    if (($matches[1] -like "*(*") -eq $true) { $matches[1].Split('(')[1].Split(')')[0] }
    else { $matches[1] }
  }
}

function GPUCurrentMode {
  #returns if the GPU is running in TCC or WDDM mode
  $nvidiaarg = "-i 0 --query-gpu=driver_model.current --format=csv,noheader"
  $nvidiasmi = "c:\program files\nvidia corporation\nvsmi\nvidia-smi"
  try { Invoke-Expression "& `"$nvidiasmi`" $nvidiaarg" }
  catch { $null }
}

function queryOS {
  #sets OS support
  if (($system.OS_Version -like "*Windows 10*") -eq $true) { $gpu.osid = '57'; $system.OS_Supported = $false }
  elseif (($system.OS_Version -like "*Windows 8.1*") -eq $true) { $gpu.osid = "41"; $system.OS_Supported = $false }
  elseif (($system.OS_Version -like "*Server 2016*") -eq $true) { $gpu.osid = "74"; $system.OS_Supported = $true }
  elseif (($system.OS_Version -like "*Server 2019*") -eq $true) { $gpu.osid = "74"; $system.OS_Supported = $true }
  else { $system.OS_Supported = $false }
}

function webName {
  #Gets the unknown GPU name from a csv based on a deviceID found in the installedgpuid function
  (New-Object System.Net.WebClient).DownloadFile("https://raw.githubusercontent.com/parsec-cloud/Cloud-GPU-Updater/master/Additional%20Files/GPUID.csv",$($system.Path + "\GPUID.CSV"))
  Import-Csv "$($system.path)\GPUID.csv" -Delimiter ',' | Where-Object DeviceID -Like *$($gpu.Device_ID)* | Select-Object -ExpandProperty GPUName
}

function queryGPU {
  #sets details about current gpu
  if ($gpu.Device_ID -eq "DEV_13F2") { $gpu.Name = 'NVIDIA Tesla M60'; $gpu.psid = '75'; $gpu.pfid = '783'; $gpu.NV_GRID = $true; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "Yes" }
  elseif ($gpu.Device_ID -eq "DEV_118A") { $gpu.Name = 'NVIDIA GRID K520'; $gpu.psid = '94'; $gpu.pfid = '704'; $gpu.NV_GRID = $true; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "Yes" }
  elseif ($gpu.Device_ID -eq "DEV_1BB1") { $gpu.Name = 'NVIDIA Quadro P4000'; $gpu.psid = '73'; $gpu.pfid = '840'; $gpu.NV_GRID = $false; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "Yes" }
  elseif ($gpu.Device_ID -eq "DEV_1BB0") { $gpu.Name = 'NVIDIA Quadro P5000'; $gpu.psid = '73'; $gpu.pfid = '823'; $gpu.NV_GRID = $false; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "Yes" }
  elseif ($gpu.Device_ID -eq "DEV_15F8") { $gpu.Name = 'NVIDIA Tesla P100'; $gpu.psid = '103'; $gpu.pfid = '822'; $gpu.NV_GRID = $true; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "UnOfficial" }
  elseif ($gpu.Device_ID -eq "DEV_1BB3") { $gpu.Name = 'NVIDIA Tesla P4'; $gpu.psid = '103'; $gpu.pfid = '831'; $gpu.NV_GRID = $true; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "UnOfficial" }
  elseif ($gpu.Device_ID -eq "DEV_1EB8") { $gpu.Name = 'NVIDIA Tesla T4'; $gpu.psid = '110'; $gpu.pfid = '883'; $gpu.NV_GRID = $true; $gpu.Driver_Version = driverversion; $gpu.Web_Driver = webdriver; $gpu.Update_Available = ($gpu.Web_Driver -gt $gpu.Driver_Version); $gpu.Current_Mode = GPUCurrentMode; $gpu.supported = "UnOfficial" }
  elseif ($gpu.Device_ID -eq $null) { $gpu.supported = "No"; $gpu.Name = "No Device Found" }
  else { $gpu.supported = "No"; $gpu.Name = webName }
}

function checkGPUSupport {
  #quits if GPU isn't supported
  if ($gpu.supported -eq "No") {
    $app.FailGPU
    exit
  }
  elseif ($gpu.supported -eq "UnOfficial") {
    $app.UnOfficialGPU
  }
  else {}
}

function checkDriverInstalled {
  #Tells user if no GPU driver is installed
  if ($system.Valid_NVIDIA_Driver -eq $False) {
    $app.NoDriver
  }
  else {}
}

function prepareEnvironment {
  #prepares working directory
  $test = Test-Path -Path $system.Path
  if ($test -eq $true) {
    Remove-Item -Path $system.Path -Recurse -Force | Out-Null
    New-Item -ItemType Directory -Force -Path $system.Path | Out-Null }
  else {
    New-Item -ItemType Directory -Force -Path $system.Path | Out-Null
  }
}

function startUpdate {
  #Gives user an option to start the update, and sends messages to the user
  prepareEnvironment
  downloaddriver
  InstallDriver
  rebootlogic
}

function setnvsmi {
  #downloads script to set GPU to WDDM if required
  (New-Object System.Net.WebClient).DownloadFile("https://raw.githubusercontent.com/parsec-cloud/Cloud-GPU-Updater/master/Additional%20Files/NVSMI.ps1",$($system.Path) + "\NVSMI.ps1")
  Unblock-File -Path "$($system.Path)\NVSMI.ps1"
}

function setnvsmi-shortcut {
  #creates startup shortcut that will start the script downloaded in setnvsmi
  Write-Output "Create NVSMI shortcut"
  $Shell = New-Object -ComObject ("WScript.Shell")
  $ShortCut = $Shell.CreateShortcut("$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup\NVSMI.lnk")
  $ShortCut.TargetPath = "powershell.exe"
  $ShortCut.Arguments = '-WindowStyle hidden -ExecutionPolicy Bypass -File "C:\ParsecTemp\Drivers\NVSMI.ps1"'
  $ShortCut.WorkingDirectory = "C:\ParsecTemp\Drivers";
  $ShortCut.WindowStyle = 0;
  $ShortCut.Description = "Create NVSMI shortcut";
  $ShortCut.Save()
}

function downloaddriver {
  if (($gpu.supported -eq "UnOfficial") -eq $true) {
    (New-Object System.Net.WebClient).DownloadFile($($($URL.GoogleGRID).Links | Where-Object href -Like *server2016_64bit_international.exe*).href,"C:\ParsecTemp\Drivers\GoogleGRID.exe")
  }
  else {
    #downloads driver from nvidia.com
    $Download.Link = Invoke-WebRequest -Uri $gpu.URL -Method Get -UseBasicParsing | Select-Object @{ N = 'Latest'; E = { $($_.Links.href -match "www.nvidia.com/download/driverResults.aspx*")[0].substring(2) } }
    $download.Direct = Invoke-WebRequest -Uri $download.Link.latest -Method Get -UseBasicParsing | Select-Object @{ N = 'Download'; E = { "http://us.download.nvidia.com" + $($_.Links.href -match "/content/driverdownload*").Split('=')[1].Split('&')[0] } }
    (New-Object System.Net.WebClient).DownloadFile($($download.Direct.download),$($system.Path) + "\NVIDIA_" + $($gpu.Web_Driver) + ".exe")
  }
}

function InstallDriver {
  #installs driver silently with /s /n arguments provided by NVIDIA
  $DLpath = Get-ChildItem -Path $system.Path -Include *exe* -Recurse | Select-Object -ExpandProperty Name
  Start-Process -FilePath "$($system.Path)\$dlpath" -ArgumentList "/s /n" -Wait }

#setting up arrays below
$url = @{}
$download = @{}
$app = @{}
$gpu = @{ Device_ID = installedGPUID }
$system = @{ Valid_NVIDIA_Driver = ValidDriver; OS_Version = osVersion; OS_Reboot_Required = RequiresReboot; Date = Get-Date; Path = "C:\ParsecTemp\Drivers" }

function rebootlogic {
  #checks if machine needs to be rebooted, and sets a startup item to set GPU mode to WDDM if required
  if ($system.OS_Reboot_Required -eq $true) {
    if ($GPU.NV_GRID -eq $false)
    {
      Start-Sleep -s 10
      Restart-Computer -Force }
    elseif ($GPU.NV_GRID -eq $true) {
      setnvsmi
      setnvsmi-shortcut
      Start-Sleep -s 10
      Restart-Computer -Force }
    else {}
  }
  else {
    if ($gpu.NV_GRID -eq $true) {
      setnvsmi
      setnvsmi-shortcut
      Start-Sleep -s 10
      Restart-Computer -Force }
    elseif ($gpu.NV_GRID -eq $false) {
    }
    else {}
  }
}

#remove Windows Proxy
clear-proxy

#fix gpu
EnableDisabledGPU
prepareEnvironment
queryOS
querygpu
querygpu
checkGPUSupport
querygpu

if (($gpu.supported -eq "Yes") -or ($gpu.supported -eq "UnOfficial")) {}
else {
  Write-Host "There is no GPU or it is unsupported"
  exit
}

if ($gpu.Driver_Version -eq $null) {
  Write-Host "No Driver"
  startUpdate
}
else { "Continue" }
if ($gpu.Current_Mode -eq "TCC") {
  Write-Host "Change Driver Mode"
  setnvsmi
  setnvsmi-shortcut
  shutdown /r -t 0 }
else {}
