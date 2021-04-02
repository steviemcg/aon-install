param(
    [Parameter(Mandatory)] [string] $InstallRoot,
    [Parameter(Mandatory)] [string] $DownloadBase,
    [Parameter(Mandatory)] [string] $SolrVersion,
    [Parameter(Mandatory)] [string] $SolrHost,
    [Parameter(Mandatory)] [string] $SolrPort,
    [Parameter(Mandatory)] [string] $SqlServer,
    [Parameter(Mandatory)] [string] $SqlAdminUser,
    [Parameter(Mandatory)] [string] $SqlAdminPassword,
	[Parameter(Mandatory)] [string] $IakCfpPassword,
    [string] $SifVersion    
) 

Write-Host "================= Enabling IIS features =================" -foregroundcolor Magenta
#Enable-WindowsOptionalFeature -featurename IIS-WebServerRole -all -online

New-Item -ItemType Directory $InstallRoot -ErrorAction SilentlyContinue

Import-Module "$PSScriptRoot\ParTech.SimpleInstallScripts.psd1" -Force

Invoke-CommandWithEffectiveParameters "Enable-ContainedDatabaseAuthentication" $PSBoundParameters

Register-SitecoreGallery
Install-SitecoreInstallFramework

Invoke-CommandWithEffectiveParameters "Install-Solr" $PSBoundParameters
Install-SifPrerequisites -InstallRoot $InstallRoot

Write-Host "================= Installing SSL certificates =================" -foregroundcolor Magenta
Import-Certificate -FilePath "$PSScriptRoot\OneGini-TST.cer" -CertStoreLocation Cert:\LocalMachine\My
Import-Certificate -FilePath "$PSScriptRoot\NAM-qc.cer" -CertStoreLocation Cert:\LocalMachine\My

$IakCfpPasswordSecure = ConvertTo-SecureString $IakCfpPassword -AsPlainText -Force
Import-PfxCertificate -FilePath "$PSScriptRoot\iakcfp.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $IakCfpPasswordSecure