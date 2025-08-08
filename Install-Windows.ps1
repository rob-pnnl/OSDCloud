Write-Host -ForegroundColor Cyan "Starting Rob's OSDCloud ..."
Start-Sleep -Seconds 1

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
Write-Host -ForegroundColor Green "We could do something here? Maybe..."
Start-Sleep -Seconds 10

$URL = "https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/481e196a-f580-4b50-afda-44ff25dcee2e/public/windows11.0-kb5064489-x64_6640d1a7a2a393bd2db6f97b7eb4fe3907806902.msu"
$OutputPath = "C:\OSDCloud\Updates\windows11.0-kb5064489-x64.msu"

# Create directory
New-Item -Path "C:\OSDCloud\Updates" -ItemType Directory -Force | Out-Null

# Download
Write-Host "Downloading Windows Update..." -ForegroundColor Yellow
try {
  #Invoke-WebRequest -Uri $URL -OutFile $OutputPath -UseBasicParsing
  Save-WebFile -SourceURL $URL -DestinationDirectory "C:\OSDCloud\Updates" -DestinationName "windows11.0-kb5064489-x64.msu"
  Write-Host "Download completed: $OutputPath" -ForegroundColor Green
}
catch {
  Write-Error "Download failed: $($_.Exception.Message)"
}



$WindowsPath = "C:\"
#$MSUPath = "D:\OSDCloud\Automate\kb5064489.msu"
$MSUPath = "C:\OSDCloud\Updates\windows11.0-kb5064489-x64.msu"
New-Item -Path "C:\OSDCloud\" -Name "scratch" -ItemType Directory
$scratchDir = "C:\OSDCLoud\scratch"
dism /Image:$WindowsPath /scratchdir:$scratchDir /Add-Package /PackagePath:$MSUPath

Start-Sleep -Seconds 30

Restart-Computer
