#Write-Host -ForegroundColor Cyan "Starting OSDCloud v2 (Windows 11 26H2 + Live ESD + M365 Apps) ..."
Start-Sleep -Seconds 1
cls

#region CONFIGURATION
$DeployConfig = [ordered]@{
    OSName                 = 'Windows 11 26H2 x64'
    OSBuild                = '26H2'
    OSLanguage             = 'en-us'
    OSEdition              = 'Enterprise'
    OSActivation           = 'Volume'
    SyncLiveMicrosoftESD   = $true
    StageM365Apps          = $true
    ConfigXmlUrl           = 'https://raw.githubusercontent.com/rob-pnnl/OSDCloud/refs/heads/main/configuration.xml'
    OdtDownloadPageUrl     = 'https://www.microsoft.com/en-us/download/details.aspx?id=49117'
    OdtFallbackDirectUrl   = 'https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20527-20150.exe'
    MinimumOSDModuleVer    = [version]'26.10.16.1'
}

# Optional manual patch override (disabled by default because live 26H2 svc_refresh ESDs
# from Microsoft's UpdateMetadataService already have the monthly Cumulative Update baked in).
$ManualKBOverride = [ordered]@{
    Enabled       = $false
    CumulativeKB  = ''
    CumulativeURL = ''
    SafeOSKB      = ''
    SafeOSURL     = ''
}
#endregion CONFIGURATION

#region TRANSCRIPT LOGGING (writes to WinPE ramdisk; copied to C:\OSDCloud\Logs before reboot)
$transcriptPath = 'X:\OSDCloud\Logs\Install-Windows-v2.log'
try {
    $transcriptDir = Split-Path -Path $transcriptPath -Parent
    if (-not (Test-Path -LiteralPath $transcriptDir)) {
        New-Item -Path $transcriptDir -ItemType Directory -Force | Out-Null
    }
    Start-Transcript -Path $transcriptPath -Append -ErrorAction SilentlyContinue | Out-Null
    Write-Host ("Transcript started: {0}" -f $transcriptPath) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("    Target OS: {0} ({1} / {2}) | Live ESD Sync: {3} | Pre-Install M365: {4}" -f `
        $DeployConfig.OSName, $DeployConfig.OSEdition, $DeployConfig.OSActivation, `
        $DeployConfig.SyncLiveMicrosoftESD, $DeployConfig.StageM365Apps) -ForegroundColor Green
} catch {
    Write-Warning (("Could not start transcript: {0}" -f $_.Exception.Message))
}
#endregion TRANSCRIPT LOGGING

#region HELPER FUNCTIONS
function Write-TextUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $utf8NoBom)
}

function Repair-OSDMsUpCatClass {
    param([Parameter(Mandatory = $true)][string]$ModuleRoot)
    $classFiles = Get-ChildItem -Path $ModuleRoot -Recurse -Filter 'MsUpCat.Class.ps1' -ErrorAction SilentlyContinue
    foreach ($cf in $classFiles) {
        try {
            $raw = [System.IO.File]::ReadAllText($cf.FullName)
            if ($raw -match 'Invoke-ParseDate') {
                $old = '$this.LastUpdated = (Invoke-ParseDate -DateString $Cells[4].innerText.Trim())'
                $new = '$__mucDate = $Cells[4].innerText.Trim().Split("/"); $this.LastUpdated = (Get-Date -Year $__mucDate[2] -Month $__mucDate[0] -Day $__mucDate[1])'
                if ($raw.Contains($old)) {
                    $raw = $raw.Replace($old, $new)
                    Write-TextUtf8NoBom -LiteralPath $cf.FullName -Content $raw
                    Write-Host ("Patched MsUpCat.Class.ps1 in {0}" -f $cf.FullName) -ForegroundColor DarkGray
                }
            }
        } catch {
            Write-Warning (("Could not patch MsUpCat.Class.ps1 at {0}: {1}" -f $cf.FullName, $_.Exception.Message))
        }
    }
}

function Sync-LatestMicrosoftOSCatalog {
    <#
    .SYNOPSIS
        Queries Microsoft's live UpdateMetadataService for the latest Windows 11 products.cab,
        verifies size and SHA256 digest, and publishes the catalog XML into OSDCloud's
        operating system catalog directories so Start-OSDCloud automatically selects the
        newest monthly svc_refresh ESD.
    #>
    [CmdletBinding()]
    param()

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $metadataUri      = 'https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo'
    $productsQuery    = 'PN=Windows.Products.Cab.amd64&V=0.0.0.0'
    $deviceAttributes = 'DUScan=1;OSVersion=10.0.26100.1'
    $tempDir          = Join-Path ([System.IO.Path]::GetTempPath()) ('osdcloud-livecat-' + [guid]::NewGuid().ToString())

    try {
        [void][System.IO.Directory]::CreateDirectory($tempDir)
        $body = ([ordered]@{
            Products         = $productsQuery
            DeviceAttributes = $deviceAttributes
        } | ConvertTo-Json -Compress)

        Write-Host -ForegroundColor Cyan "Querying Microsoft Update Metadata Service for latest Windows 11 ESD catalog..."
        $response = Invoke-RestMethod -Uri $metadataUri -Method Post -ContentType 'application/json' -Headers @{ Accept = '*/*' } -Body $body -TimeoutSec 30
        if ($response -is [array]) {
            $response = $response | Select-Object -First 1
        }

        $cabRecord = $response.FileLocations | Where-Object { $_.FileName -eq 'products.cab' } | Select-Object -First 1
        if ($null -eq $cabRecord -or [string]::IsNullOrWhiteSpace($cabRecord.Url)) {
            Write-Warning "Microsoft metadata response did not include a products.cab URL. Using bundled catalog."
            return $null
        }

        $cabPath = Join-Path $tempDir 'products.cab'
        $xmlPath = Join-Path $tempDir 'products.xml'
        Invoke-WebRequest -Uri $cabRecord.Url -OutFile $cabPath -UseBasicParsing -TimeoutSec 60

        if (-not (Test-Path -LiteralPath $cabPath)) {
            Write-Warning "products.cab download did not produce a file. Using bundled catalog."
            return $null
        }

        # Verify SHA256 digest if provided by Microsoft metadata
        if (-not [string]::IsNullOrWhiteSpace($cabRecord.Digest)) {
            $expectedBytes = [Convert]::FromBase64String([string]$cabRecord.Digest)
            $expectedHex   = ([System.BitConverter]::ToString($expectedBytes)).Replace('-', '').ToUpperInvariant()
            $actualHex     = (Get-FileHash -LiteralPath $cabPath -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($expectedHex -ne $actualHex) {
                Write-Warning (("products.cab SHA256 mismatch (Expected {0}, Got {1}). Using bundled catalog." -f $expectedHex, $actualHex))
                return $null
            }
        }

        $expandExe = Join-Path (Join-Path $env:SystemRoot 'System32') 'expand.exe'
        & $expandExe $cabPath $xmlPath | Out-Null
        if (-not (Test-Path -LiteralPath $xmlPath)) {
            Write-Warning "Failed to expand products.cab. Using bundled catalog."
            return $null
        }

        [xml]$catXml = Get-Content -LiteralPath $xmlPath -Raw -ErrorAction Stop
        $fileNodes = @($catXml.MCT.Catalogs.Catalog.PublishedMedia.Files.File)
        if ($fileNodes.Count -lt 10) {
            Write-Warning "Extracted products.xml contained fewer than 10 ESD records. Using bundled catalog."
            return $null
        }

        $catalogIdentity = $null
        foreach ($fn in $fileNodes) {
            if ($fn.FileName -match '^(?<Identity>\d{5}\.(?:0|[1-9]\d*)\.\d{6}-\d{4})\.') {
                $catalogIdentity = $Matches['Identity']
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($catalogIdentity)) {
            Write-Warning "Could not determine <major>.<ubr>.<timestamp> identity from products.xml. Using bundled catalog."
            return $null
        }

        $catalogFileName = ("{0}.xml" -f $catalogIdentity)
        $targetDirs = @()

        if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
            $pdDir = Join-Path (Join-Path (Join-Path $env:ProgramData 'OSDeployCore') 'OSDCloud') 'catalogs\operatingsystems'
            $targetDirs += $pdDir
        }
        $targetDirs += 'X:\ProgramData\OSDeployCore\OSDCloud\catalogs\operatingsystems'

        $osdMod = Get-Module -Name OSD | Select-Object -First 1
        if ($null -eq $osdMod) {
            $osdMod = Get-Module -ListAvailable -Name OSD | Sort-Object Version -Descending | Select-Object -First 1
        }
        if ($null -ne $osdMod -and -not [string]::IsNullOrWhiteSpace($osdMod.ModuleBase)) {
            $modCatDir = Join-Path (Join-Path $osdMod.ModuleBase 'core') 'operatingsystems'
            $targetDirs += $modCatDir
        }

        foreach ($dir in ($targetDirs | Select-Object -Unique)) {
            try {
                [void][System.IO.Directory]::CreateDirectory($dir)
                $destFile = Join-Path $dir $catalogFileName
                Copy-Item -LiteralPath $xmlPath -Destination $destFile -Force -ErrorAction Stop
                Write-Host ("Published live Microsoft OS catalog -> {0}" -f $destFile) -ForegroundColor Green
            } catch {
                Write-Warning (("Could not write catalog to {0}: {1}" -f $dir, $_.Exception.Message))
            }
        }

        # Clear cached catalog variable so OSD re-imports the freshly written XML
        $global:ModuleCoreOperatingSystems = $null
        return $catalogIdentity
    } catch {
        Write-Warning (("Live Microsoft OS catalog sync failed: {0}. Falling back to bundled catalog." -f $_.Exception.Message))
        return $null
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stage-M365PreInstall {
    <#
    .SYNOPSIS
        Stages the Office Deployment Tool (setup.exe + configuration.xml) to C:\OSDCloud\ODT
        and configures C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd to install M365 Apps
        in the Full OS (SYSTEM context) before OOBE / Autopilot begins.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigXmlUrl,
        [Parameter(Mandatory = $true)][string]$OdtDownloadPageUrl,
        [Parameter(Mandatory = $true)][string]$OdtFallbackDirectUrl
    )

    Write-Host ""
    Write-Host -ForegroundColor Cyan "Staging M365 Apps (Office Deployment Tool) for pre-OOBE SetupComplete install..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $targetOdtDir = 'C:\OSDCloud\ODT'
    $targetSetupCompleteDir = 'C:\OSDCloud\Scripts\SetupComplete'
    [void][System.IO.Directory]::CreateDirectory($targetOdtDir)
    [void][System.IO.Directory]::CreateDirectory($targetSetupCompleteDir)

    $targetSetupExe  = Join-Path $targetOdtDir 'setup.exe'
    $targetConfigXml = Join-Path $targetOdtDir 'configuration.xml'

    # 1. Stage setup.exe (prefer baked copy in X:\OSDCloud\ODT\setup.exe, else download from Microsoft)
    $bakedSetupExe = 'X:\OSDCloud\ODT\setup.exe'
    if (Test-Path -LiteralPath $bakedSetupExe) {
        Copy-Item -LiteralPath $bakedSetupExe -Destination $targetSetupExe -Force
        Write-Host ("Copied baked ODT setup.exe -> {0}" -f $targetSetupExe) -ForegroundColor Green
    } else {
        Write-Host "ODT setup.exe not found in WinPE image; downloading from Microsoft..." -ForegroundColor Yellow
        $odtDownloadUrl = $OdtFallbackDirectUrl
        try {
            $page = Invoke-WebRequest -Uri $OdtDownloadPageUrl -UseBasicParsing -TimeoutSec 20
            $match = [regex]::Match($page.Content, 'https://download\.microsoft\.com/download/[^"''\s]+officedeploymenttool[^"''\s]+\.exe', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($match.Success) {
                $odtDownloadUrl = $match.Value
            }
        } catch {
            Write-Warning (("Could not scrape ODT download page; using fallback URL: {0}" -f $odtDownloadUrl))
        }

        $odtPkgPath = Join-Path $targetOdtDir 'officedeploymenttool.exe'
        Invoke-WebRequest -Uri $odtDownloadUrl -OutFile $odtPkgPath -UseBasicParsing -TimeoutSec 60
        if (Test-Path -LiteralPath $odtPkgPath) {
            $extractArgs = ("/quiet /extract:`"{0}`"" -f $targetOdtDir)
            Start-Process -FilePath $odtPkgPath -ArgumentList $extractArgs -Wait -NoNewWindow
            Remove-Item -LiteralPath $odtPkgPath -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $targetOdtDir -Filter 'configuration-*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not (Test-Path -LiteralPath $targetSetupExe)) {
        Write-Warning "ODT setup.exe could not be staged. Skipping M365 pre-install setup."
        return
    }

    # 2. Stage configuration.xml (prefer live GitHub repo copy so changes apply without WIM rebuild, fallback to baked copy)
    $bakedConfigXml = 'X:\OSDCloud\ODT\configuration.xml'
    $configStaged = $false
    try {
        Invoke-WebRequest -Uri $ConfigXmlUrl -OutFile $targetConfigXml -UseBasicParsing -TimeoutSec 20
        if ((Test-Path -LiteralPath $targetConfigXml) -and ((Get-Item -LiteralPath $targetConfigXml).Length -gt 100)) {
            $configStaged = $true
            Write-Host ("Downloaded latest configuration.xml -> {0}" -f $targetConfigXml) -ForegroundColor Green
        }
    } catch {
        Write-Warning (("Could not download live configuration.xml ({0}); checking baked fallback." -f $_.Exception.Message))
    }

    if ((-not $configStaged) -and (Test-Path -LiteralPath $bakedConfigXml)) {
        Copy-Item -LiteralPath $bakedConfigXml -Destination $targetConfigXml -Force
        $configStaged = $true
        Write-Host ("Copied baked configuration.xml -> {0}" -f $targetConfigXml) -ForegroundColor Green
    }

    if (-not $configStaged) {
        Write-Warning "configuration.xml could not be staged. Skipping M365 pre-install setup."
        return
    }

    # 3. Optional: If an attached USB/cache drive has a pre-downloaded Office\Data payload, copy it locally
    $cacheDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('C', 'X') }
    foreach ($cd in $cacheDrives) {
        $candidateOfficeDir = Join-Path (Join-Path (Join-Path $cd.Root 'OSDCloud') 'ODT') 'Office'
        if (Test-Path -LiteralPath (Join-Path $candidateOfficeDir 'Data')) {
            Write-Host ("Found cached M365 payload at {0}; copying to {1}..." -f $candidateOfficeDir, $targetOdtDir) -ForegroundColor Cyan
            Copy-Item -LiteralPath $candidateOfficeDir -Destination $targetOdtDir -Recurse -Force
            break
        }
    }

    # 4. Copy active WinPE Wi-Fi profile (if any) to C:\OSDCloud\ODT\WiFiProfile.xml so SetupComplete can reconnect if needed
    foreach ($wfCandidate in @('X:\OSDCloud\Config\Scripts\WiFiProfile.xml', 'X:\OSDCloud\Config\Scripts\StartNet\wifi.xml')) {
        if (Test-Path -LiteralPath $wfCandidate) {
            Copy-Item -LiteralPath $wfCandidate -Destination (Join-Path $targetOdtDir 'WiFiProfile.xml') -Force -ErrorAction SilentlyContinue
            break
        }
    }

    # 5. Write Install-M365Apps.ps1 to C:\OSDCloud\Scripts\SetupComplete\Install-M365Apps.ps1
    $installM365ScriptPath = Join-Path $targetSetupCompleteDir 'Install-M365Apps.ps1'
    $installM365Script = @'
<#
.SYNOPSIS
    Installs Microsoft 365 Apps during OSDCloud SetupComplete (Full OS, SYSTEM context,
    right before OOBE / Autopilot starts).
#>
$ErrorActionPreference = 'Continue'
$LogDir     = 'C:\OSDCloud\Logs'
$LogFile    = Join-Path $LogDir 'Install-M365Apps.log'
$OdtDir     = 'C:\OSDCloud\ODT'
$SetupExe   = Join-Path $OdtDir 'setup.exe'
$ConfigXml  = Join-Path $OdtDir 'configuration.xml'
$WifiXml    = Join-Path $OdtDir 'WiFiProfile.xml'

try { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null } catch {}
Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null
Write-Output ("==== Install-M365Apps (SetupComplete) started {0} ====" -f (Get-Date))

function Test-Tcp {
    param([string]$TestHost = 'officecdn.microsoft.com', [int]$Port = 443)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($TestHost, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(3000, $false) -and $c.Connected) {
            $c.EndConnect($iar)
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Wait-ForNetworkReady {
    param([int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $wifiAttempted = $false
    while ((Get-Date) -lt $deadline) {
        if ((Test-Tcp -TestHost 'officecdn.microsoft.com' -Port 443) -or (Test-Tcp -TestHost 'www.msftconnecttest.com' -Port 443)) {
            return $true
        }
        if ((-not $wifiAttempted) -and (Test-Path -LiteralPath $WifiXml)) {
            $wifiAttempted = $true
            try {
                Write-Output "Network not ready yet; attempting Wi-Fi connection using staged WiFiProfile.xml..."
                $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne 'Running') {
                    Start-Service -Name WlanSvc -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                }
                [xml]$wx = Get-Content -LiteralPath $WifiXml -Raw
                $ssid = $wx.WLANProfile.name
                netsh wlan add profile filename="$WifiXml" user=all 2>&1 | Out-Null
                if ($ssid) {
                    netsh wlan connect name="$ssid" ssid="$ssid" 2>&1 | Out-Null
                }
            } catch {}
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Sync-SystemClock {
    param([string]$Url = 'http://www.msftconnecttest.com/connecttest.txt')
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $d = $resp.Headers['Date']
        $resp.Close()
        if ($d) {
            $utc = [datetime]::Parse($d).ToUniversalTime()
            if ([math]::Abs(((Get-Date).ToUniversalTime() - $utc).TotalMinutes) -gt 5) {
                Set-Date -Date $utc.ToLocalTime() | Out-Null
                Write-Output ("System clock synchronized to {0}" -f (Get-Date))
            }
        }
    } catch {}
}

try {
    if (-not (Test-Path -LiteralPath $SetupExe)) {
        throw ("ODT setup.exe not found at {0}" -f $SetupExe)
    }
    if (-not (Test-Path -LiteralPath $ConfigXml)) {
        throw ("ODT configuration.xml not found at {0}" -f $ConfigXml)
    }

    $hasLocalCache = Test-Path -LiteralPath (Join-Path (Join-Path $OdtDir 'Office') 'Data')
    if ($hasLocalCache) {
        Write-Output "Found pre-cached Office\Data folder in C:\OSDCloud\ODT\Office."
    } else {
        Write-Output "Waiting for network connectivity to Microsoft CDN..."
        if (-not (Wait-ForNetworkReady -TimeoutSeconds 180)) {
            throw "No network connectivity available to download M365 Apps from CDN."
        }
        Sync-SystemClock
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $argList = ("/configure `"{0}`"" -f $ConfigXml)
    Write-Output ("Executing: {0} {1}" -f $SetupExe, $argList)
    $proc = Start-Process -FilePath $SetupExe -ArgumentList $argList -WorkingDirectory $OdtDir -Wait -PassThru -NoNewWindow
    $sw.Stop()
    Write-Output ("ODT setup.exe exited with code {0} after {1:N1} minutes." -f $proc.ExitCode, $sw.Elapsed.TotalMinutes)

    $c2rReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($null -ne $c2rReg -and -not [string]::IsNullOrWhiteSpace($c2rReg.VersionToReport)) {
        Write-Output ("Verified M365 Apps installed: VersionToReport={0} ProductReleaseIds={1}" -f $c2rReg.VersionToReport, $c2rReg.ProductReleaseIds)
    } else {
        Write-Output "WARNING: ClickToRun VersionToReport registry value was not found after ODT execution."
    }

    # Clean up any local Office\Data payload cache to reclaim disk space
    $officeCacheDir = Join-Path $OdtDir 'Office'
    if (Test-Path -LiteralPath $officeCacheDir) {
        Remove-Item -LiteralPath $officeCacheDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Cleaned up temporary C:\OSDCloud\ODT\Office payload cache."
    }
} catch {
    Write-Output ("ERROR in Install-M365Apps: {0}" -f $_.Exception.Message)
}

Write-Output ("==== Install-M365Apps (SetupComplete) finished {0} ====" -f (Get-Date))
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
exit 0
'@
    Write-TextUtf8NoBom -LiteralPath $installM365ScriptPath -Content $installM365Script
    Write-Host ("Staged pre-OOBE installer script -> {0}" -f $installM365ScriptPath) -ForegroundColor Green

    # 6. Ensure C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd calls both Collect-AutopilotHash.ps1 and Install-M365Apps.ps1
    $customSetupCompleteCmd = Join-Path $targetSetupCompleteDir 'SetupComplete.cmd'
    $bakedCollectHash = 'X:\OSDCloud\Config\Scripts\SetupComplete\Collect-AutopilotHash.ps1'
    $targetCollectHash = Join-Path $targetSetupCompleteDir 'Collect-AutopilotHash.ps1'
    if ((-not (Test-Path -LiteralPath $targetCollectHash)) -and (Test-Path -LiteralPath $bakedCollectHash)) {
        Copy-Item -LiteralPath $bakedCollectHash -Destination $targetCollectHash -Force
    }

    $cmdContent = @"
@echo off
REM ============================================================
REM  OSDCloud custom SetupComplete entry point (runs in FULL OS,
REM  SYSTEM context, at end of Windows Setup - before OOBE).
REM ============================================================
if exist "C:\OSDCloud\Scripts\SetupComplete\Collect-AutopilotHash.ps1" (
    %windir%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\OSDCloud\Scripts\SetupComplete\Collect-AutopilotHash.ps1"
)
if exist "C:\OSDCloud\Scripts\SetupComplete\Install-M365Apps.ps1" (
    %windir%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\OSDCloud\Scripts\SetupComplete\Install-M365Apps.ps1"
)
exit /b 0
"@
    Write-TextUtf8NoBom -LiteralPath $customSetupCompleteCmd -Content $cmdContent
    Write-Host ("Updated custom SetupComplete.cmd -> {0}" -f $customSetupCompleteCmd) -ForegroundColor Green

    # 7. Verify C:\Windows\Setup\scripts\SetupComplete.ps1 invokes C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd
    $winSetupScriptsDir = 'C:\Windows\Setup\scripts'
    $winSetupCompletePs1 = Join-Path $winSetupScriptsDir 'SetupComplete.ps1'
    if (Test-Path -LiteralPath $winSetupCompletePs1) {
        $ps1Raw = Get-Content -LiteralPath $winSetupCompletePs1 -Raw -ErrorAction SilentlyContinue
        if ($ps1Raw -notmatch 'C:\\OSDCloud\\Scripts\\SetupComplete\\SetupComplete\.cmd') {
            $hookLines = @(
                "Write-Output 'Running Scripts in Custom OSDCloud SetupComplete Folder'"
                '$SetupCompletePath = "C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd"'
                'if (Test-Path $SetupCompletePath) { cmd.exe /c $SetupCompletePath }'
            ) -join "`r`n"
            Add-Content -LiteralPath $winSetupCompletePs1 -Value "`r`n$hookLines`r`n" -Encoding ASCII
            Write-Host "Injected custom SetupComplete hook into C:\Windows\Setup\scripts\SetupComplete.ps1" -ForegroundColor Green
        }
    }
}
#endregion HELPER FUNCTIONS

#region TECHNICIAN CONFIRMATION
Write-Host ""
Write-Host ""
Write-Host "               ======================"
Write-Host -ForegroundColor Red "                    CONFIRMATION     "
Write-Host "               ======================"
Write-Host ""
$confirmation = Read-Host "   This action will wipe your computer, type 'yes' to confirm and proceed"
if ($confirmation -ieq "yes") {
    Write-Host "Proceeding with action..." -ForegroundColor Green
} else {
    Write-Host "Action cancelled. Restarting Computer" -ForegroundColor Yellow
    Restart-Computer -Force
}

Start-Sleep -Seconds 2
# Change Display Resolution for Virtual Machine
if ((Get-MyComputerModel) -match 'Virtual') {
    Write-Host -ForegroundColor Cyan "Setting Display Resolution to 1600x"
    Set-DisRes 1600
}
#endregion TECHNICIAN CONFIRMATION

#region OSD MODULE VERIFICATION & LIVE CATALOG SYNC
$availableOSD = Get-Module -ListAvailable -Name OSD | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $availableOSD -or $availableOSD.Version -lt $DeployConfig.MinimumOSDModuleVer) {
    $foundVer = if ($null -ne $availableOSD) { $availableOSD.Version.ToString() } else { 'None' }
    Write-Host -ForegroundColor Yellow ("OSD module in image is {0} (< {1}). Installing latest OSD module for 26H2 support..." -f $foundVer, $DeployConfig.MinimumOSDModuleVer)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-Module -Name OSD -Force -Scope AllUsers -SkipPublisherCheck -ErrorAction Stop
        $newOSD = Get-Module -ListAvailable -Name OSD | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -ne $newOSD) {
            Repair-OSDMsUpCatClass -ModuleRoot $newOSD.ModuleBase
        }
    } catch {
        Write-Warning (("Failed to update OSD module online: {0}" -f $_.Exception.Message))
    }
}

Write-Host -ForegroundColor Cyan "Importing OSD PowerShell Module..."
Import-Module OSD -Force

if ($DeployConfig.SyncLiveMicrosoftESD) {
    $liveCatalogId = Sync-LatestMicrosoftOSCatalog
    if ($liveCatalogId) {
        Write-Host -ForegroundColor Green ("Live Microsoft ESD catalog active: {0}" -f $liveCatalogId)
    }
}

try {
    $resolvedFU = Get-FeatureUpdate -OSName $DeployConfig.OSName -OSActivation $DeployConfig.OSActivation -OSLanguage $DeployConfig.OSLanguage
    if ($null -ne $resolvedFU) {
        Write-Host ""
        Write-Host -ForegroundColor Green ("Resolved Target ESD : {0}" -f $resolvedFU.Name)
        Write-Host -ForegroundColor Green ("Resolved ESD Build  : {0}" -f $resolvedFU.Build)
        Write-Host -ForegroundColor DarkGray ("Resolved ESD File   : {0}" -f $resolvedFU.FileName)
        Write-Host ""
    }
} catch {
    Write-Warning (("Could not preview Get-FeatureUpdate: {0}" -f $_.Exception.Message))
}
#endregion OSD MODULE VERIFICATION & LIVE CATALOG SYNC

#region START OSDCLOUD DEPLOYMENT
Write-Host -ForegroundColor Cyan ("Starting OSDCloud ({0} {1} {2})..." -f $DeployConfig.OSName, $DeployConfig.OSEdition, $DeployConfig.OSActivation)
Start-OSDCloud -OSName $DeployConfig.OSName -OSLanguage $DeployConfig.OSLanguage -OSEdition $DeployConfig.OSEdition -OSActivation $DeployConfig.OSActivation -SkipAutopilot
#endregion START OSDCLOUD DEPLOYMENT

Write-Host -ForegroundColor Cyan "Starting OSDCloud PostAction ..."
Start-Sleep -Seconds 1

#region OPTIONAL MANUAL PATCH OVERRIDE (Skipped by default since live 26H2 ESD is pre-patched)
if ($ManualKBOverride.Enabled -and -not [string]::IsNullOrWhiteSpace($ManualKBOverride.CumulativeURL)) {
    Write-Host -ForegroundColor Yellow ("Manual KB override enabled ({0}). Downloading and applying..." -f $ManualKBOverride.CumulativeKB)
    New-Item -Path 'C:\OSDCloud\Updates' -ItemType Directory -Force | Out-Null
    New-Item -Path 'C:\OSDCloud\scratch' -ItemType Directory -Force | Out-Null
    $msuPath = 'C:\OSDCloud\Updates\latestKB.msu'
    try {
        Save-WebFile -SourceURL $ManualKBOverride.CumulativeURL -DestinationDirectory 'C:\OSDCloud\Updates' -DestinationName 'latestKB.msu'
        dism /Image:C:\ /scratchdir:C:\OSDCloud\scratch /Add-Package /PackagePath:$msuPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warning (("DISM Add-Package returned exit code {0} for {1}." -f $LASTEXITCODE, $ManualKBOverride.CumulativeKB))
        } else {
            Write-Host -ForegroundColor Cyan ("Manual cumulative patch installed ({0})" -f $ManualKBOverride.CumulativeKB)
        }
    } catch {
        Write-Warning (("Manual cumulative update failed: {0}" -f $_.Exception.Message))
    }

    if (-not [string]::IsNullOrWhiteSpace($ManualKBOverride.SafeOSURL)) {
        $safeOSPath = 'C:\OSDCloud\Updates\SafeOS.cab'
        $winreWim   = 'C:\Windows\System32\Recovery\winre.wim'
        $mountDir   = 'C:\OSDCloud\WinRE_Mount'
        try {
            Save-WebFile -SourceURL $ManualKBOverride.SafeOSURL -DestinationDirectory 'C:\OSDCloud\Updates' -DestinationName 'SafeOS.cab'
            New-Item -Path $mountDir -ItemType Directory -Force | Out-Null
            DISM /Mount-Image /ImageFile:$winreWim /Index:1 /MountDir:$mountDir
            if ($LASTEXITCODE -ne 0) { throw ("Mount-Image failed (exit {0})" -f $LASTEXITCODE) }
            DISM /Image:$mountDir /Add-Package /PackagePath:$safeOSPath
            DISM /Unmount-Image /MountDir:$mountDir /Commit
            Write-Host -ForegroundColor Cyan ("WinRE patched with Safe OS update ({0})" -f $ManualKBOverride.SafeOSKB)
        } catch {
            Write-Warning (("WinRE SafeOS patch failed: {0}. Attempting discard unmount." -f $_.Exception.Message))
            DISM /Unmount-Image /MountDir:$mountDir /Discard 2>&1 | Out-Null
        }
    }
} else {
    Write-Host -ForegroundColor Green "Skipping offline DISM .msu step (live Microsoft 26H2 svc_refresh ESD already includes monthly Cumulative Update)."
}
#endregion OPTIONAL MANUAL PATCH OVERRIDE

#region STAGE M365 APPS FOR SETUPCOMPLETE
if ($DeployConfig.StageM365Apps) {
    try {
        Stage-M365PreInstall `
            -ConfigXmlUrl $DeployConfig.ConfigXmlUrl `
            -OdtDownloadPageUrl $DeployConfig.OdtDownloadPageUrl `
            -OdtFallbackDirectUrl $DeployConfig.OdtFallbackDirectUrl
    } catch {
        Write-Warning (("M365 Apps pre-install staging encountered an error: {0}" -f $_.Exception.Message))
    }
}
#endregion STAGE M365 APPS FOR SETUPCOMPLETE

#region PERSIST TRANSCRIPT TO C: BEFORE REBOOT
try {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    $persistDir = 'C:\OSDCloud\Logs'
    if (-not (Test-Path -LiteralPath $persistDir)) {
        New-Item -Path $persistDir -ItemType Directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $transcriptPath) {
        Copy-Item -LiteralPath $transcriptPath -Destination (Join-Path $persistDir 'Install-Windows-v2.log') -Force -ErrorAction SilentlyContinue
    }
} catch {}
#endregion PERSIST TRANSCRIPT TO C: BEFORE REBOOT

Start-Sleep -Seconds 15
Restart-Computer
