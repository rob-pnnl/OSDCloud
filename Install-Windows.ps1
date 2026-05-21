#Write-Host -ForegroundColor Cyan "Starting OSDCloud ..."
Start-Sleep -Seconds 1
cls

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

#Start OSDCloud ZTI the RIGHT way
Write-Host -ForegroundColor Cyan "Start OSDCloud with new Parameters"
#Start-OSDCloud -OSLanguage en-us -OSVersion 'Windows 11' -OSBuild 24H2 -OSEdition Enterprise -OSActivation Volume -ZTI -SkipAutopilot

# Bypass disk verification and rely on earlier Confirmation
#Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -ZTI -SkipAutopilot

Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -SkipAutopilot

# Innate Prompt to verify wiping disk
#Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -SkipAutopilot

Write-Host -ForegroundColor Cyan "Starting OSDCloud PostAction ..."
Write-Host -ForegroundColor Green "Let's check for patches..."
Start-Sleep -Seconds 1


#region INSTALL LATEST CUMULATIVE UPDATE

# $URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9d6e2b81-b755-4e68-af73-9f4ee41cd758/public/windows11.0-kb5072033-x64_a62291f0bad9123842bf15dcdd75d807d2a2c76a.msu"  #Dec 2025  25H2
# $URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/df3e807e-9c9c-448e-93ce-63477b39d7f9/public/windows11.0-kb5078127-x64_2669c24d8d8227e7992853d32fb4e95873bbe6bf.msu"  #Jan 2026  25H2  w/ Out of Band
# $URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/80d1ded6-1dbd-41de-84ff-790373be83c8/public/windows11.0-kb5085516-x64_52aef89bc1afc5e67eec927556ec6926122936ad.msu" #March 2026
# $URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/ca944ac5-63da-42b4-9d1f-58b0c3259132/public/windows11.0-kb5083769-x64_57f4bd47d73842dd239f2c18b8ce48c8bf1c1d5d.msu"  #April 2026

$URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/53914338-2058-4b75-95a6-6d674648107c/public/windows11.0-kb5089549-x64_9a542b5813b003374532dceeba49b7e07c3fc2fb.msu" #May 2026

$OutputPath = "C:\OSDCloud\Updates\latestKB.msu"
# Create directory
New-Item -Path "C:\OSDCloud\Updates" -ItemType Directory -Force | Out-Null

# Download
Write-Host "Downloading Windows Update..." -ForegroundColor Yellow
try {
  #Invoke-WebRequest -Uri $URL -OutFile $OutputPath -UseBasicParsing
  #Save-WebFile -SourceURL $URL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "windows11.0-kb5064489-x64.msu"
  Save-WebFile -SourceURL $URL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "latestKB.msu"
  Write-Host "Download completed: $OutputPath" -ForegroundColor Green
}
catch {
  Write-Error "Download failed: $($_.Exception.Message)"
}

$WindowsPath = "C:\"
#$MSUPath = "D:\OSDCloud\Automate\kb5064489.msu"
#$MSUPath = "C:\OSDCloud\Updates\windows11.0-kb5064489-x64.msu"
$MSUPath = "C:\OSDCloud\Updates\latestKB.msu"
New-Item -Path "C:\OSDCloud\" -Name "scratch" -ItemType Directory
$scratchDir = "C:\OSDCLoud\scratch"
dism /Image:$WindowsPath /scratchdir:$scratchDir /Add-Package /PackagePath:$MSUPath
Write-Host -ForegroundColor Cyan "Latest Windows cumulative patch installed"

$SafeOSURL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9e3d3c09-fbf6-4dd2-8cc9-a07d4dcd5879/public/windows11.0-kb5089593-x64_2ec8272439ac21bbba6df2f4befdda6f63c22858.cab"
$SafeOSPath = "C:\OSDCloud\Updates\SafeOS.cab"
$WinREWim = "C:\Windows\System32\Recovery\winre.wim"
$MountDir = "C:\OSDCloud\WinRE_Mount"
Save-WebFile -SourceURL $SafeOSURL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "SafeOS.cab"

New-Item -Path $MountDir -ItemType Directory -Force | Out-Null
DISM /Mount-Image /ImageFile:$WinREWim /Index:1 /MountDir:$MountDir
DISM /Image:$MountDir /Add-Package /PackagePath:$SafeOSPath
DISM /Unmount-Image /MountDir:$MountDir /Commit
Write-Host -ForegroundColor Cyan "WinRE patched with Safe OS update"

Start-Sleep -Seconds 15
#endregion INSTALL LATEST CUMULATIVE UPDATE

Restart-Computer
