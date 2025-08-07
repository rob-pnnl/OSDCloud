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
Start-Sleep -Seconds 5

$WindowsPath = C:\
$MSUPath = X:\OSDCloud\Automate\kb5064489.msu
dism /Image:$WindowsPath /Add-Package /PackagePath:$MSUPath

Start-Sleep -Seconds 5

Restart-Computer
