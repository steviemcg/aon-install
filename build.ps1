param(
    [Parameter(Mandatory)] [string] $DownloadBase,
    [Parameter(Mandatory)] [string] $BizTalkAon,
    [Parameter(Mandatory)] [string] $BizTalkForms,
    [Parameter(Mandatory)] [string] $SqlServer,
    [Parameter(Mandatory)] [string] $SqlAdminUser,
    [Parameter(Mandatory)] [string] $SqlAdminPassword
)

$ErrorActionPreference = "Stop"

$sourceFolder = "C:\eglobal_au\Dev\aon-sitecore\code\sitecore\src"
$installRoot = "C:\downloads\910XP0"
$prefix = "cfpa"
$SitecorePath = "C:\\eBusiness\\sites\\$prefix.local"
$XConnectPath = "C:\\eBusiness\\sites\\$prefix.xconnect.local"
$DevSettingsFile = "$PSScriptRoot\DevSettings.config"
$SitecoreBuild = "1.30.0.205"
$FrontendSitecoreBuild = "1.1.0-281"

$packages = @(
    "Sitecore JavaScript Services Server for Sitecore 9.1 XP 11.0.0 rev. 181031.zip"
    "Sitecore.PowerShell.Extensions-6.2.zip"
    "Sitecore Experience Accelerator 1.8 rev. 181112 for 9.1.zip"
    "SXA Solr Cores.zip"
    "Templates backup 2021-03-31a.zip"
    "Content backup 2021-03-31.zip"
    "Media backup 2021-03-31.zip"
)

$zips = @(
    "9.1.0 Hotfixes.zip"
    "razl.zip"
)

Write-Host "================= Installing ParTech.SimpleInstallScripts =================" -foregroundcolor Magenta
Import-Module "$PSScriptRoot\ParTech.SimpleInstallScripts.psd1" -Force

Write-Host "================= Downloading files =================" -foregroundcolor Magenta
$filesToDownload = $packages + $zips + @("cfpa.sitecore.react.$($SitecoreBuild).zip", "XConnectFiles.zip", "aon-front-end-sitecore.$($FrontendSitecoreBuild).tgz", "cfpa.sitecore.dotnet.$($SitecoreBuild).zip")

foreach ($fileName in $filesToDownload) {
    Write-Host "================= Downloading $fileName =================" -foregroundcolor Yellow
    $FileUrl = "$DownloadBase/$fileName"
    $FilePath = "$($installRoot)\$fileName"
    Invoke-DownloadIfNeeded $FileUrl $FilePath
}

$ConnectionStrings = @{
    "session" = "localhost:6379"
    "bizTalkAon" = $BizTalkAon
    "bizTalkForms" = $BizTalkForms
    "SiteTransferServiceCert" = "B066A86A7D929DE78800C0C67BB7975BC7AD6398"
    "HouseInfoUrl" = "http://adres.dev.aon.nl/AdresGegevens/gethouseinfo"
    "ZorgWebUrl" = "BaseUrl=https://ws-test.z-advies.nl/apps/rest/AON_OneUnderwritingjs/sessiedata/{guid};username=;password=;useProxy=false"
}

Write-Host "================= Checking Redis installed =================" -foregroundcolor Magenta
$redis = Test-NetConnection -ComputerName 127.0.0.1 -Port 6379
if (-Not $redis.TcpTestSucceeded) {
    throw "Please install Redis first. G:\ECOMM.AFD\CFP\Developer Workstation Tools"
}

Invoke-SetXmlTask -FilePath $DevSettingsFile -XPath "//sitecore/sc.variable[@name='sourceFolder']" -Attributes @{value=$sourceFolder}

# TODO: publishingsettings.targets.user

Install-Sitecore91 -Prefix $prefix `
                -Parameters @{Path=".\\aon.json"; SitecoreSiteName="$prefix.local"; SitecorePath=$SitecorePath; SitecoreSchema="https"; DevSettingsFile=$DevSettingsFile; InstallRoot=$installRoot } `
                -SitecoreVersion 910XP0 `
                -DownloadBase $DownloadBase `
                -SqlServer $SqlServer `
                -SqlAdminUser $SqlAdminUser `
                -SqlAdminPassword $SqlAdminPassword `
                -SitecoreAdminPassword b `
                -Packages $packages `
                -Zips $zips `
                -ConnectionStrings $ConnectionStrings `
                -DoUninstall:$false `
                -DoInstallPrerequisites:$true `
                -DoSitecorePublish:$false `
                -DoRebuildLinkDatabases:$true `
                -DoRebuildSearchIndexes:$true `
                -DoDeployMarketingDefinitions:$true

Write-Host "================= Extracting CFP Sitecore solution =================" -foregroundcolor Magenta
Expand-Archive -Path "$installRoot\cfpa.sitecore.dotnet.$($SitecoreBuild).zip" -DestinationPath $SitecorePath -Force
& ".\slowcheetah.xdt.exe" "$SitecorePath\web.config" "$sourceFolder\Website\Web.Local.config" "$SitecorePath\web.config"

Write-Host "================= Extracting JavaScript SSR app =================" -foregroundcolor Magenta
New-Item "$SitecorePath\dist" -ItemType Directory -Force
tar -zxf "$installRoot\aon-front-end-sitecore.$($FrontendSitecoreBuild).tgz"
Move-Item "$PSScriptRoot\package" "$SitecorePath\dist\aon_app"

Write-Host "================= Extracting AuditLog app =================" -foregroundcolor Magenta
New-Item "$SitecorePath\sitecore\cfpa\auditlog" -ItemType Directory -Force
Expand-Archive -Path "$installRoot\cfpa.sitecore.react.$($SitecoreBuild).zip" -DestinationPath "$SitecorePath\sitecore\cfpa\auditlog" -Force

Write-Host "================= Extracting XConnect files =================" -foregroundcolor Magenta
Expand-Archive -Path "$installRoot\XconnectFiles.zip" -DestinationPath $XConnectPath -Force

Test-Site "https://$prefix.local"

Write-Host "================= Running Unicorn =================" -foregroundcolor Magenta
Add-Type -Path "$SitecorePath\bin\MicroCHAP.dll"
Import-Module $PSScriptRoot\Unicorn.psm1 -Force
Sync-Unicorn -ControlPanelUrl "https://$prefix.local/unicorn.aspx" -SharedSecret 'B117AA7E8140B7B3C106FBE16D5DB8FDAA2F4F04EA175B251D22B8FB23A7891D' -StreamLogs

Test-Site "https://$prefix.local"
Write-Host "Done!" -foregroundcolor Green