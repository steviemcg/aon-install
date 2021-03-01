param(
    [Parameter(Mandatory)] [string] $DownloadBase
)

$ErrorActionPreference = "Stop"

Enable-WindowsOptionalFeature -featurename IIS-WebServerRole -all -online

Install-Module ParTech.SimpleInstallScripts

$packages = @(
	"Sitecore.PowerShell.Extensions-6.2.zip"
	"Sitecore Experience Accelerator 1.8 rev. 181112 for 9.1.zip"
	"Sitecore JavaScript Services Server for Sitecore 9.1 XP 11.0.0 rev. 181031.zip",
	"Templates backup-20210301.zip"
	"Content backup-20210301.zip"
	"Media backup-20210301.zip"
)

# files
# auditlog
# dist/aon_app
# connectionstrings adjustment

Install-Sitecore91 -Prefix cfpa `
				  -SitecoreVersion 910XP0 `
				  -DownloadBase $DownloadBase `
				  -SqlServer . `
				  -SqlAdminUser sa `
				  -SqlAdminPassword 'Password12!' `
				  -DoInstallPrerequisites `
				  -Packages $packages `
				  -DoSitecorePublish
				  -DoRebuildLinkDatabases `
				  -DoRebuildSearchIndexes `
				  -DoDeployMarketingDefinitions