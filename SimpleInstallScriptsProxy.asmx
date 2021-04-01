<%@ WebService Language="C#" Class="SimpleInstallScriptsProxy" %>
using System;
using System.ComponentModel;
using System.Configuration;
using System.IO;
using System.Linq;
using System.Web.Services;
using System.Xml;
using Sitecore;
using Sitecore.Configuration;
using Sitecore.ContentSearch;
using Sitecore.ContentSearch.Maintenance;
using Sitecore.Data;
using Sitecore.Data.Engines;
using Sitecore.Data.Events;
using Sitecore.Data.Managers;
using Sitecore.Install;
using Sitecore.Install.Files;
using Sitecore.Install.Framework;
using Sitecore.Install.Items;
using Sitecore.Install.Utils;
using Sitecore.Jobs;
using Sitecore.Publishing;
using Sitecore.SecurityModel;
using Sitecore.Update;
using Sitecore.Update.Installer;
using Sitecore.Update.Installer.Utils;
using InstallMode = Sitecore.Update.Utils.InstallMode;
using log4net;
using log4net.Config;

[WebService(Namespace = "http://tempuri.org/")]
[WebServiceBinding(ConformsTo = WsiProfiles.BasicProfile1_1)]
[ToolboxItem(false)]
public class SimpleInstallScriptsProxy : WebService
{
    [WebMethod(Description = "Installs a Sitecore Zip or Update Package.")]
    public void InstallPackage(string path)
    {
        var file = new FileInfo(path);  
        if (!file.Exists)
        {
            throw new ApplicationException(string.Format("Cannot access path '{0}'.", path));
        }

        if (file.Extension == ".update")
        {
            InstallUpdatePackage(path);
        }
        else
        {
            InstallZipPackage(path);
        }
    }

    [WebMethod(Description = "Publishes a database")]
    public void SmartPublish(string sourceDatabaseName, string targetDatabaseName)
    {
        var sourceDatabase = Factory.GetDatabase(sourceDatabaseName);
        var targetDatabase = Factory.GetDatabase(targetDatabaseName);
        Database[] targets = { targetDatabase };

        var languages = LanguageManager.GetLanguages(sourceDatabase).ToArray();
        PublishManager.PublishSmart(sourceDatabase, targets, languages);
    }

    [WebMethod(Description = "Determines if any jobs are running")]
    public bool AreJobsRunning()
    {
        return JobManager.GetJobs().Any(x => !x.IsDone);
    }

    [WebMethod(Description = "Rebuilds a Link Database")]
    public void RebuildLinkDatabase(string databaseName)
    {
        JobManager.Start(new DefaultJobOptions(string.Format("RebuildLinkDatabase-{0}", databaseName), "SimpleInstallScripts", "shell", this, "RebuildLinkDatabaseInternal", new object[] { databaseName }));
    }

    [WebMethod(Description = "Rebuilds a search index")]
    public void RebuildSearchIndex(string indexName)
    {
        var index = ContentSearchManager.GetIndex(indexName);
        IndexCustodian.FullRebuild(index);
    }

    private void InstallUpdatePackage(string path)
    {
        var log = LogManager.GetLogger("root");
        XmlConfigurator.Configure((XmlElement)ConfigurationManager.GetSection("log4net"));

        using (new SecurityDisabler())
        {
            var installer = new DiffInstaller(UpgradeAction.Upgrade);
            var view = UpdateHelper.LoadMetadata(path);
            
            string historyPath;
            bool hasPostAction;
            var entries = installer.InstallPackage(path, InstallMode.Install, log, out hasPostAction, out historyPath);
            installer.ExecutePostInstallationInstructions(path, historyPath, InstallMode.Install, view, log, ref entries);
            UpdateHelper.SaveInstallationMessages(entries, historyPath);
        }
    }

    private static void InstallZipPackage(string path)
    {
        Sitecore.Context.SetActiveSite("shell");

        using (new SecurityDisabler())  
        {  
            using (new SyncOperationContext())  
            {  
                var context = new SimpleProcessingContext();
                var options = new BehaviourOptions(Sitecore.Install.Utils.InstallMode.Overwrite, MergeMode.Undefined);
                context.AddAspect(new DefaultItemInstallerEvents(options));  
                context.AddAspect(new DefaultFileInstallerEvents(true));  
          
                var installer = new Installer();  
                installer.InstallPackage(path, context);  
            }  
        }  
    }

    private void RebuildLinkDatabaseInternal(string databaseName)
    {
        var database = Factory.GetDatabase(databaseName);
        Globals.LinkDatabase.Rebuild(database);
    }
}