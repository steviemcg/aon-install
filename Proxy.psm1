Set-StrictMode -Version 2.0

Function Install-SimpleInstallScriptsProxies {
    param(
        [Parameter(Mandatory)] [string] $SiteFolder
    )

    Write-Host "Installing Simple Install Scripts Proxies"
    Copy-Item -Path "$PSScriptRoot\SimpleInstallScripts*.asmx" -Destination $SiteFolder
}

Function Remove-SimpleInstallScriptsProxies {
    param(
        [Parameter(Mandatory)] [string] $SiteFolder
    )

    Write-Host "Deleting Simple Install Scripts Proxy"
    
    $installerPath = Join-Path $SiteFolder "SimpleInstallScripts*.asmx"
    Remove-Item -Path $installerPath -ErrorAction SilentlyContinue
}

Function Test-Site {
    param([Parameter(Mandatory)][string] $Url)  
    Write-Host "Pinging $Url" -ForegroundColor Magenta
    $test = Invoke-WebRequest -Uri $url -TimeoutSec 600 -UseBasicParsing
    $test.Content | Out-Null
}

Function Invoke-WaitForJobsToFinish {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)] $proxy
    )

    $jobsRunning = $true
    Write-Host "Waiting for $Name to finish" -ForegroundColor Yellow

    while ($jobsRunning) {
        $jobsRunning = $proxy.AreJobsRunning()
        Write-Host "." -NoNewline
        
        if ($jobsRunning) {
            Start-Sleep 5
        } else {
            Write-Host " done"
        }
    }
}