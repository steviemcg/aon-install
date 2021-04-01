Set-StrictMode -Version 2.0

Function Invoke-EnsureAdmin() {
    $elevated = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    if ($elevated -eq $false)
    {
        throw "Please run this script as an administrator"
    }
}

Function Register-SitecoreGallery() {
    Get-PSRepository -Name "SitecoreGallery" -ErrorVariable ev1 -ErrorAction SilentlyContinue | out-null
    If ($null -eq $ev1 -or $ev1.count -eq 0)
    {
      return
    }

    Write-Host "================= Installing Sitecore PowerShell Gallery =================" -foregroundcolor "green"    
    
    Get-PackageProvider -Name Nuget -ForceBootstrap
    Register-PSRepository -Name "SitecoreGallery" `
                          -SourceLocation "https://sitecore.myget.org/F/sc-powershell/api/v2" `
                          -InstallationPolicy Trusted | Out-Null

    Write-Host "PowerShell repository `"SitecoreGallery`" has been registered." -ForegroundColor Green
}

Function Install-SitecoreInstallFramework(
    [string] $Version
) {
    Register-SitecoreGallery

    Write-Host "================= Installing Sitecore Install Framework =================" -foregroundcolor "green"    

    if (!$Version) {
        [array] $sifModules = Find-Module -Name "SitecoreInstallFramework" -Repository "SitecoreGallery"
        $latestSIFModule = $sifModules[-1]
        $Version = $latestSIFModule.Version.ToString()
    }

    Install-Module -Name "SitecoreInstallFramework" -Repository "SitecoreGallery" -Force -Scope AllUsers -SkipPublisherCheck -AllowClobber -RequiredVersion $Version
}

Function Enable-ModernSecurityProtocols() {
    Write-Host "================= Enabling modern security protocols =================" -foregroundcolor "green"    
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

Function Install-SifPrerequisites(
    [Parameter(Mandatory)] [string] $InstallRoot
) {
    Write-Host "================= Installing SIF Prerequisites =================" -foregroundcolor "green"
    $config = Resolve-Path "$InstallRoot\Prerequisites.json"
    Install-SitecoreConfiguration $config
}

Function Install-Solr(
    [Parameter(Mandatory)] [string] $SolrVersion,
    [Parameter(Mandatory)] [string] $SolrHost,
    [Parameter(Mandatory)] [string] $SolrPort
) {
    Write-Host "================= Installing Solr Server =================" -foregroundcolor "green"
    
    Try {
        Push-Location $PSScriptRoot
        $config = Resolve-Path "$PSScriptRoot\Solr-SingleDeveloper.json"
        Install-SitecoreConfiguration $config `
            -SolrVersion $SolrVersion `
            -SolrDomain $SolrHost `
            -SolrPort $SolrPort
    } Finally {
        Pop-Location
    }
}

Function Install-AllPrerequisites(
    [Parameter(Mandatory)] [string] $InstallRoot,
    [Parameter(Mandatory)] [string] $DownloadBase,
    [Parameter(Mandatory)] [string] $SolrVersion,
    [Parameter(Mandatory)] [string] $SolrHost,
    [Parameter(Mandatory)] [string] $SolrPort,
    [Parameter(Mandatory)] [string] $SqlServer,
    [Parameter(Mandatory)] [string] $SqlAdminUser,
    [Parameter(Mandatory)] [string] $SqlAdminPassword,
    [string] $SifVersion    
) {
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "================= Installing All Prerequisites =================" -foregroundcolor "green"

    Invoke-EnsureAdmin
    Install-SitecoreInstallFramework -Version $SifVersion
    Install-SifPrerequisites -InstallRoot $InstallRoot
    Invoke-CommandWithEffectiveParameters "Install-Solr" $PSBoundParameters
    Invoke-CommandWithEffectiveParameters "Enable-ContainedDatabaseAuthentication" $PSBoundParameters

    Write-Host "Successfully setup environment (time: $($elapsed.Elapsed.ToString()))"
}

Function Invoke-DownloadPackages (
    [Parameter(Mandatory)] [string] $DownloadBase,
    [Parameter(Mandatory)] [string] $InstallRoot,
    [Parameter(Mandatory)] [string] $WdpsZipName,
    [Parameter(Mandatory)] [string] $ConfigsZipName
) {
    Write-Host "================= Downloading packages =================" -foregroundcolor "green"    
    New-Item -ItemType Directory -Force -Path $InstallRoot

    $WdpsUrl = "$DownloadBase/$WdpsZipName"
    $WdpsZip = "$InstallRoot\$WdpsZipName"
    Invoke-DownloadIfNeeded $WdpsUrl $WdpsZip
    Expand-Archive $WdpsZip -DestinationPath $InstallRoot -Force
    
    $ConfigFilesZip = "$InstallRoot\$ConfigsZipName"
    Expand-Archive $ConfigFilesZip -DestinationPath $InstallRoot -Force

    Invoke-DownloadIfNeeded "$DownloadBase/license.xml" "$InstallRoot\license.xml"
}

Function Enable-ContainedDatabaseAuthentication
(
    [Parameter(Mandatory)] [string] $SqlServer, # The DNS name or IP of the SQL Instance.
    [Parameter(Mandatory)] [string] $SqlAdminUser, # A SQL user with sysadmin privileges.
    [Parameter(Mandatory)] [string] $SqlAdminPassword # The password for $SQLAdminUser.
)
{
    Write-Host "================= Enabling Contained Database Authentication =================" -foregroundcolor "green"    
    sqlcmd -S $SqlServer -U $SqlAdminUser -P $SqlAdminPassword -h-1 -Q "sp_configure 'contained database authentication', 1; RECONFIGURE;"
}

Function Invoke-DownloadIfNeeded
(
    [Parameter(Mandatory)] [string] $source,
    [Parameter(Mandatory)] [string] $target
)
{
    Write-Host "Invoke-DownloadIfNeeded to $target"
    if (Test-Path $target) {
        Write-Debug "Already exists"
        return
    }
    
    $client = (New-Object System.Net.WebClient)
    $client.DownloadFile($source, $target)
}

Function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
 
    process {
        $hash = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = $property.Value
        }

        Return $hash
    }
}

Function Get-DefaultSitecoreParameters
{
    param([parameter(Mandatory)] [string] $SitecoreVersion)    

    $DefaultsPath = "$PSScriptRoot\Defaults\$($SitecoreVersion).json"
    If (!(Test-Path($DefaultsPath))) {
        throw "Defaults not found: $DefaultsPath"
    }

    Return Get-Content -Raw -Path $DefaultsPath | ConvertFrom-Json | ConvertTo-Hashtable
}