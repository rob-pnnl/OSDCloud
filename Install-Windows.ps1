#Write-Host -ForegroundColor Cyan "Starting OSDCloud ..."
Start-Sleep -Seconds 1
cls

#region MONTHLY KB CONFIG -- update these 4 values each Patch Tuesday cycle, then commit & push
# History: previous URLs are kept commented in the INSTALL LATEST CUMULATIVE UPDATE region below.
$KBConfig = [ordered]@{
    OSBuild       = '25H2'
    LastUpdated   = '2026-05-XX'   # tracking only, not used by script
    CumulativeKB  = 'KB5089549'    # May 2026
    CumulativeURL = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/53914338-2058-4b75-95a6-6d674648107c/public/windows11.0-kb5089549-x64_9a542b5813b003374532dceeba49b7e07c3fc2fb.msu'
    SafeOSKB      = 'KB5089593'
    SafeOSURL     = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9e3d3c09-fbf6-4dd2-8cc9-a07d4dcd5879/public/windows11.0-kb5089593-x64_2ec8272439ac21bbba6df2f4befdda6f63c22858.cab'
}
#endregion

#region TRANSCRIPT LOGGING (writes to WinPE ramdisk; copied to C:\OSDCloud\Logs before reboot)
$transcriptPath = 'X:\OSDCloud\Logs\Install-Windows.log'
try {
    New-Item -Path (Split-Path $transcriptPath -Parent) -ItemType Directory -Force | Out-Null
    Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Transcript started: $transcriptPath" -ForegroundColor DarkGray
    Write-Host "KB Config: CU=$($KBConfig.CumulativeKB)  SafeOS=$($KBConfig.SafeOSKB)  Build=$($KBConfig.OSBuild)" -ForegroundColor DarkGray
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

<#
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
#>

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
