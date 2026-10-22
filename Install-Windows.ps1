#Write-Host -ForegroundColor Cyan "Starting OSDCloud ..."
Start-Sleep -Seconds 1
cls

#region MONTHLY KB CONFIG -- update these 4 values each Patch Tuesday cycle, then commit & push
# History: previous URLs are kept commented in the INSTALL LATEST CUMULATIVE UPDATE region below.
$KBConfig = [ordered]@{
    OSBuild       = '25H2'
    LastUpdated   = '2026-10-22'   # Tracking only
    CumulativeKB  = 'KB5127648'    # August 2026
    DateStamp     = 'October 2026'
    CumulativeURL = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/4225b261-8248-43e5-a808-34f3faafe3f6/public/windows11.0-kb5127648-x64_2b88d2d308adc938fcd4d2876a68ee0b2a3c4c09.msu'
    SafeOSKB      = 'KB5127654'
    SafeOSURL     = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f8397943-4d37-43cb-a167-74b567556f37/public/windows11.0-kb5127654-x64_87d6bc65b7b39cdd33e9570c7aff97e28ba31c2b.cab'
}
#endregion

<#old data
$KBConfig = [ordered]@{
    OSBuild       = '25H2'
    LastUpdated   = '2026-09-15'   # Tracking only
    CumulativeKB  = 'KB5124008'    # August 2026
    DateStamp     = 'September 2026'
    CumulativeURL = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/ed315343-4767-4a66-9be5-2a23bef1546e/public/windows11.0-kb5124008-x64_81e42f50fdb7af8d15eefc23aa51cf3e23215bdc.msu'
    SafeOSKB      = 'KB5124015'
    SafeOSURL     = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/0832cdac-2b64-4fff-9628-e934f9cef112/public/windows11.0-kb5124015-x64_8d6045779da371cd3ffd1bf768a4d053ba9110c7.cab'
}
#>

#region TRANSCRIPT LOGGING (writes to WinPE ramdisk; copied to C:\OSDCloud\Logs before reboot)
$transcriptPath = 'X:\OSDCloud\Logs\Install-Windows.log'
try {
    New-Item -Path (Split-Path $transcriptPath -Parent) -ItemType Directory -Force | Out-Null
    Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Transcript started: $transcriptPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ""
    Write-Host "    Build=$($KBConfig.OSBuild)   KB Config: CU=$($KBConfig.CumulativeKB)  $($KBConfig.DateStamp)" -ForegroundColor Green
} catch {
    Write-Warning "Could not start transcript: $($_.Exception.Message)"
}
#endregion

Write-Host ""
Write-Host ""
Write-Host "               ======================"
Write-Host -ForegroundColor Red "                    CONFIRMATION     "
Write-Host "               ======================"
Write-Host ""
$confirmation = Read-Host "   This action will wipe your computer, type 'yes' to confirm and proceed"
if ($confirmation -ieq "yes") {
  Write-Host "Proceeding with action..." -ForegroundColor Green
}
else {
  Write-Host "Action cancelled. Restarting Computer" -ForegroundColor Yellow
  Restart-Computer -Force
}

Start-Sleep -Seconds 2
#Change Display Resolution for Virtual Machine
if ((Get-MyComputerModel) -match 'Virtual') {
    Write-Host -ForegroundColor Cyan "Setting Display Resolution to 1600x"
    Set-DisRes 1600
}

#Make sure I have the latest OSD Content
Write-Host -ForegroundColor Cyan "Updating the awesome OSD PowerShell Module"
#Install-Module OSD -Force

Write-Host -ForegroundColor Cyan "Importing the sweet OSD PowerShell Module"
Import-Module OSD -Force

#TODO: Spend the time to write a function to do this and put it here
Write-Host -ForegroundColor Cyan "Ejecting ISO"
#Write-Warning "That didn't work because I haven't coded it yet!"
#Start-Sleep -Seconds 5

# Bypass disk verification and rely on earlier Confirmation
#Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -ZTI -SkipAutopilot     # This wipes disk without verifying

# Start OSDCloud ZTI the RIGHT way
Write-Host -ForegroundColor Cyan "Start OSDCloud with new Parameters"
Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -SkipAutopilot  # Innate Prompt to verify wiping disk


Write-Host -ForegroundColor Cyan "Starting OSDCloud PostAction ..."
Write-Host -ForegroundColor Green "Let's check for patches..."
Start-Sleep -Seconds 1


#region INSTALL LATEST CUMULATIVE UPDATE

# $URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/ca944ac5-63da-42b4-9d1f-58b0c3259132/public/windows11.0-kb5083769-x64_57f4bd47d73842dd239f2c18b8ce48c8bf1c1d5d.msu"  #April 2026

# Active CU URL is sourced from $KBConfig at top of script (was previously hard-coded here)
$URL = $KBConfig.CumulativeURL

$OutputPath = "C:\OSDCloud\Updates\latestKB.msu"
# Create directory
New-Item -Path "C:\OSDCloud\Updates" -ItemType Directory -Force | Out-Null

# Download
Write-Host "Downloading Windows Update..." -ForegroundColor Yellow
try {
  Save-WebFile -SourceURL $URL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "latestKB.msu"
  Write-Host "Download completed: $OutputPath" -ForegroundColor Green
}
catch {
  Write-Error "Download failed: $($_.Exception.Message)"
}

$WindowsPath = "C:\"
$MSUPath = "C:\OSDCloud\Updates\latestKB.msu"
New-Item -Path "C:\OSDCloud\" -Name "scratch" -ItemType Directory -Force | Out-Null
$scratchDir = "C:\OSDCLoud\scratch"
try {
  dism /Image:$WindowsPath /scratchdir:$scratchDir /Add-Package /PackagePath:$MSUPath
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "DISM Add-Package returned exit code $LASTEXITCODE for cumulative update $($KBConfig.CumulativeKB). Continuing."
  } else {
    Write-Host -ForegroundColor Cyan "Latest Windows cumulative patch installed ($($KBConfig.CumulativeKB))"
  }
} catch {
  Write-Warning "DISM cumulative update install threw: $($_.Exception.Message). Continuing."
}

#endregion INSTALL LATEST CUMULATIVE UPDATE
Start-Sleep -Seconds 5


#region WinRE 
# Active SafeOS URL is sourced from $KBConfig at top of script
$SafeOSURL = $KBConfig.SafeOSURL
$SafeOSPath = "C:\OSDCloud\Updates\SafeOS.cab"
$WinREWim = "C:\Windows\System32\Recovery\winre.wim"
$MountDir = "C:\OSDCloud\WinRE_Mount"
Save-WebFile -SourceURL $SafeOSURL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "SafeOS.cab"

New-Item -Path $MountDir -ItemType Directory -Force | Out-Null
try {
  DISM /Mount-Image /ImageFile:$WinREWim /Index:1 /MountDir:$MountDir
  if ($LASTEXITCODE -ne 0) { throw "Mount-Image failed (exit $LASTEXITCODE)" }

  DISM /Image:$MountDir /Add-Package /PackagePath:$SafeOSPath
  $addExit = $LASTEXITCODE

  DISM /Unmount-Image /MountDir:$MountDir /Commit
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Unmount /Commit returned $LASTEXITCODE -- WinRE may not have been updated."
  } elseif ($addExit -ne 0) {
    Write-Warning "SafeOS Add-Package returned $addExit (image still committed)."
  } else {
    Write-Host -ForegroundColor Cyan "WinRE patched with Safe OS update ($($KBConfig.SafeOSKB))"
  }
} catch {
  Write-Warning "WinRE SafeOS patch failed: $($_.Exception.Message). Attempting discard unmount."
  DISM /Unmount-Image /MountDir:$MountDir /Discard 2>&1 | Out-Null
}
#endregion WinRE
#


#region PERSIST TRANSCRIPT TO C: BEFORE REBOOT
try {
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
  $persistDir = 'C:\OSDCloud\Logs'
  New-Item -Path $persistDir -ItemType Directory -Force | Out-Null
  if (Test-Path $transcriptPath) {
    Copy-Item -Path $transcriptPath -Destination (Join-Path $persistDir 'Install-Windows.log') -Force -ErrorAction SilentlyContinue
  }
} catch {}
#endregion


Start-Sleep -Seconds 15
Restart-Computer
