param(
    [Parameter(Mandatory)] [string] $DownloadBase
)

$ErrorActionPreference = "Stop"

Import-Module ParTech.SimpleInstallScripts

Install-Sitecore91 -Prefix cfpa `
				  -SitecoreVersion 910XP0 `
				  -DownloadBase $DownloadBase `
				  -SqlServer . `
				  -SqlAdminUser sa `
				  -SqlAdminPassword 'Password12!' `
				  -DoInstallPrerequisites `
				  -Packages @("Sitecore.PowerShell.Extensions-6.2.zip") `
				  -DoSitecorePublish
				  -DoRebuildLinkDatabases `
				  -DoRebuildSearchIndexes `
				  -DoDeployMarketingDefinitions