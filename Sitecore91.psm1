Set-StrictMode -Version 2.0

Function Install-Sitecore91 (
    [Parameter(Mandatory)] [string] $Prefix, # The Prefix that will be used on SOLR, Website and Database instances.
    [Parameter(Mandatory)] [string] $SitecoreVersion, # i.e. 901XM0, 910XP0, 911XP1, etc.
    [Parameter(Mandatory)] [string] $DownloadBase, # The location where WDPs, ZIPs, license.xml are stored
    [Parameter(Mandatory)] [string] $SQLServer, # The DNS name or IP of the SQL Instance.
    [Parameter(Mandatory)] [string] $SqlAdminUser, # A SQL user with sysadmin privileges.
    [Parameter(Mandatory)] [string] $SqlAdminPassword, # The password for $SQLAdminUser.
    [string] $SitecoreAdminPassword, # The Password for the Sitecore Admin User. This will be regenerated if left on the default.
    [string] $DriveLetter = "C", # The desired drive to install Sitecore on, and download assets
    [string] $SolrHost = "localhost", # The hostname of the Solr server
    [string] $SolrPort = "8983", # The port of the Solr server
    [Hashtable] $Parameters = @{}, # Parameters for Install-SitecoreConfiguration
    [string[]] $Packages = @(), # Packages to install
    [string[]] $Zips = @(), # Zips to extract
    [Hashtable] $ConnectionStrings = @{}, # Extra ConnectionStrings to add
    [switch] $DoUninstall, # Uninstalls Sitecore instead of installing
    [switch] $DoInstallPrerequisites, # Install SIF, Solr, etc.
    [switch] $DoSitecorePublish, # If the Sitecore master database should be published to web
    [switch] $DoRebuildLinkDatabases, # If the Link Databases should be rebuilt
    [switch] $DoRebuildSearchIndexes, # If the Search Indexes should be rebuilt
    [switch] $DoDeployMarketingDefinitions # If the Marketing Definitions should be deployed
)
{
    $ErrorActionPreference = "Stop"

    # TODO: Support Dynamic Parameters based on what the SIF Configuration supports, so no need for @Parameters variable
    # TODO: Check SQL admin now. (2016+ if 9 + XP)
    
    if (!$DoInstallPrerequisites) {
        # TODO: Check Java + JAVA_HOME now
        # TODO: Check Solr now
    }

    Write-Host "================= Normalizing Parameters =================" -foregroundcolor "green"

    $WhitelistParameters = @(
        "InstallRoot", 
        "Topology", 
        "Mode", 
        "SifVersion", 
        "SifConfigurationName",
        "WdpsZipName",
        "ConfigsZipName",
        "SitecoreSchema",
        "SitecoreUrl",
        "SitecorePath",
        "SolrVersion"
    )

    # Adds all string parameters to the $Parameters variable to be splatted to various functions
    foreach ($h in $MyInvocation.MyCommand.Parameters.GetEnumerator()) {
        $Key = $h.Key
        $WhitelistParameters += $Key

        If ($h.Value.ParameterType.Name -eq "String") {
            $Value = Get-Variable $Key -ValueOnly -EA SilentlyContinue

            If ($Value) {
                $Parameters.$Key = $Value
            }
        }
    }

    # Enrich the $Parameters with default values from this version of Sitecore so we can use them later below
    $Defaults = Get-DefaultSitecoreParameters $Parameters.SitecoreVersion
    foreach ($key in $Defaults.Keys) {
        If (!$Parameters.ContainsKey($key) -Or !$Parameters.$key) {
            $Parameters.$key = $ExecutionContext.InvokeCommand.ExpandString($Defaults.$key)
        }
    }
    
    # Downloads the WDPs and Configs for this Sitecore version
    Invoke-CommandWithEffectiveParameters "Invoke-DownloadPackages" $Parameters

    If (!$Parameters.ContainsKey("Path")) {
        # Uses the default Json configuration supplied in the Configs zip
        $Parameters.Path = "$($Parameters.InstallRoot)\$($Parameters.SifConfigurationName)"

        If ($Parameters.Topology -eq "XM0") {
            # XM0 isn't delivered by Sitecore, so work around that by removing the SitecoreCD include
            $json = Get-Content -Path $Parameters.Path -Raw | ConvertFrom-Json
            $json.Includes.PSObject.Properties.Remove("SitecoreCD")

            $Parameters.Path = "$($Parameters.InstallRoot)\XM0-SingleDeveloper.json"
            $json | ConvertTo-Json -Depth 100 | Set-Content -Path $Parameters.Path -Force
        }
    }

    If ($DoInstallPrerequisites) {
        # Registers the Sitecore PowerShell Gallery, installs Sitecore Install Framework, the correct version of Solr, etc.        
        Invoke-CommandWithEffectiveParameters "Install-AllPrerequisites" $Parameters
    }

    Write-Host "================= Ensuring Valid Parameters =================" -foregroundcolor "green"

    $SitecoreConfigurationParameterNames = Get-ParameterNamesFromSitecoreConfiguration $Parameters.Path
    $SitecoreConfigurationParameterNames += Get-ParameterNamesFromCommand "Install-SitecoreConfiguration"

    # Ensures all the extra parameters supplied (also from the defaults) will be recognised by SIF
    # Throwing an exception is perhaps a bit strong but this method ensures the configs don't have redundant properties.
    foreach ($key in $Parameters.Keys) {
        If (!$SitecoreConfigurationParameterNames.Contains($key) -And !$WhitelistParameters.Contains($key)) {
            throw "Unknown parameter name for Install-SitecoreConfiguration: $key"
        }
    }

    Try {
        # Does all the work in the context of where the WDPs and Configs were downloaded
        Copy-Item .\*.json -Force -Destination $Parameters.InstallRoot
        Push-Location $Parameters.InstallRoot

        # Determines the parameters that can be splatted to SIF
        $SitecoreParams = Get-EffectiveParameters $SitecoreConfigurationParameterNames $Parameters
        Write-Debug (ConvertTo-Json $SitecoreParams).ToString()

        If ($DoUninstall) {
            Write-Host "================= Unstalling $Prefix =================" -foregroundcolor Yellow
            Uninstall-SitecoreConfiguration @SitecoreParams *>&1 | Tee-Object "$($Prefix)-Uninstall.log"
        } else {
            Write-Host "================= Installing $Prefix =================" -foregroundcolor Yellow
            Install-SitecoreConfiguration @SitecoreParams *>&1 | Tee-Object "$($Prefix).log"

            $WebConfigFile = Join-Path $Parameters.SitecorePath "Web.config"

            If ($Parameters.Topology -eq "XM0") {
                # As Sitecore don't deliver XM0, change Sitecore Role from ContentManagement to Standalone
                Invoke-SetXmlTask -FilePath $WebConfigFile -XPath "//configuration/appSettings/add[@key='role:define']" -Attributes @{value="Standalone"}
            }
            
            Invoke-SetXmlTask -FilePath $WebConfigFile -XPath "//configuration/system.web/httpRuntime" -Attributes @{executionTimeout="1800"}

            If ($ConnectionStrings.Count -gt 0) {
				Write-Host "================= Adjusting ConnectionStrings =================" -foregroundcolor Magenta
				
                $ConnectionStringsFile = "$($Parameters.SitecorePath)\App_Config\ConnectionStrings.config"
                foreach ($key in $ConnectionStrings.Keys) {
                    Invoke-SetXmlTask -FilePath $ConnectionStringsFile -XPath "//connectionStrings" -Element add -Attributes @{name=$key; connectionString=$ConnectionStrings[$Key]}
                }
            }

            # Tests if the homepage loads
            Test-Site $Parameters.SitecoreUrl

            # Installs the .asmx agent to the Content Management / Standalone instance
            Install-SimpleInstallScriptsProxies $Parameters.SitecorePath
            $proxy = New-WebServiceProxy -uri "$($Parameters.SitecoreUrl)/SimpleInstallScriptsProxy91.asmx?WSDL"
            $proxy.Timeout = 1800000			
            
            # Installs .zip and .update packages, such as Sitecore PowerShell Extensions-5.1.zip
            foreach ($PackageName in $Packages) {
                Write-Host "================= Installing Package $PackageName =================" -foregroundcolor Magenta
                $PackagesUrl = "$DownloadBase/$PackageName"
                $PackagesZip = "$($Parameters.InstallRoot)\$PackageName"
                Invoke-DownloadIfNeeded $PackagesUrl $PackagesZip
                $proxy.InstallPackage($PackagesZip)
                Test-Site $Parameters.SitecoreUrl
            }
            
            # Extracts Zips
            foreach ($ZipName in $Zips) {
                Write-Host "================= Installing Zip $ZipName =================" -foregroundcolor Magenta
                $ZipUrl = "$DownloadBase/$ZipName"
                $Zip = "$($Parameters.InstallRoot)\$ZipName"
                Invoke-DownloadIfNeeded $ZipUrl $Zip
                Expand-Archive $Zip -Destination $Parameters.SitecorePath -Force
                Test-Site $Parameters.SitecoreUrl
            }
                       
            # Executes a Smart Publish
            if ($DoSitecorePublish) {
                Write-Host "================= Publishing master to web =================" -foregroundcolor Magenta
                $proxy.SmartPublish('master', 'web')
                Invoke-WaitForJobsToFinish "Smart Publish" $proxy
            }

            # Rebuilds the Core and Master Link databases. Shame this isn't done by Sitecore!
            if ($DoRebuildLinkDatabases) {
                Write-Host "================= Rebuilding Link Databases =================" -foregroundcolor Magenta
                Write-Host "Rebuilding Core Link Database" -ForegroundColor Yellow
                $proxy.RebuildLinkDatabase("core")

                Write-Host "Rebuilding Master Link Database" -ForegroundColor Yellow
                $proxy.RebuildLinkDatabase("master")
                
                Invoke-WaitForJobsToFinish "Rebuilding Link Databases" $proxy
            }
            
            # Rebuilds the core, master and web indexes
            # TODO: Loop through and rebuild *all* indexes
            if ($DoRebuildSearchIndexes) {
                Write-Host "================= Rebuilding Search Databases =================" -foregroundcolor Magenta
                Write-Host "Rebuilding Core Search Index" -ForegroundColor Yellow
                $proxy.RebuildSearchIndex("sitecore_core_index")

                Write-Host "Rebuilding Master Search Index" -ForegroundColor Yellow
                $proxy.RebuildSearchIndex("sitecore_master_index")

                Write-Host "Rebuilding Web Search Index" -ForegroundColor Yellow
                $proxy.RebuildSearchIndex("sitecore_web_index")
                
                Invoke-WaitForJobsToFinish "Rebuilding Search Indexes" $proxy
            }
            
            if ($Parameters.Mode -eq "XP") {
                $proxyXP = New-WebServiceProxy -uri "$($Parameters.SitecoreUrl)/SimpleInstallScriptsProxyXP91.asmx?WSDL"
                $proxyXP.Timeout = 1800000
    
                # Deploys the Marketing Definitions. This can take a *long* time. Again, would be nice if they were pre-deployed by Sitecore.
                if ($DoDeployMarketingDefinitions) {
                    Write-Host "================= Deploying Marketing Definitions =================" -foregroundcolor Magenta
                    $proxyXP.DeployMarketingDefinitions()
                    Invoke-WaitForJobsToFinish "Deploying Marketing Definitions" $proxy
                }
            }

            # Removes the agent to remove the security hole
            # TODO: Consider moving the agent under /sitecore/admin and logging in like SIF's PopulateManagedSchema.aspx
            Remove-SimpleInstallScriptsProxies $Parameters.SitecorePath

            # Ensures the site still works
            Test-Site $Parameters.SitecoreUrl
        }
    } Finally {
        Pop-Location
    }
}