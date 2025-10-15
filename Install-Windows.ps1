Write-Host -ForegroundColor Cyan "Starting Rob's OSDCloud ..."
Start-Sleep -Seconds 1

Write-Host -ForegroundColor Red "CONFIRMATION"
$confirmation = Read-Host "This action will wipe your computer, type 'yes' to confirm and proceed"
if ($confirmation -ieq "yes") {
  Write-Host "Proceeding with action..." -ForegroundColor Green
  
}
else {
  Write-Host "Action cancelled. Restarting Computer" -ForegroundColor Yellow
  Restart-Computer -Force
}

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
Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage en-us -OSEdition Enterprise -OSActivation Volume -ZTI -SkipAutopilot

Write-Host -ForegroundColor Cyan "Starting OSDCloud PostAction ..."
Write-Host -ForegroundColor Green "We could do something here? Maybe we check for patches..."
Start-Sleep -Seconds 5


#region INSTALL LATEST CUMULATIVE UPDATE

#$URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/6d57381b-2334-4031-acd9-549c3611e767/public/windows11.0-kb5063878-x64_c2d51482402fd8fc112d2c022210dd7c3266896d.msu" #August 2025

$URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7342fa97-e584-4465-9b3d-71e771c9db5b/public/windows11.0-kb5065426-x64_32b5f85e0f4f08e5d6eabec6586014a02d3b6224.msu" #Sept 2025

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
Start-Sleep -Seconds 30
#endregion INSTALL LATEST CUMULATIVE UPDATE

Restart-Computer
