<%@ WebService Language="C#" Class="SimpleInstallScriptsProxy" %>
using System.Collections.Generic;
using System.ComponentModel;
using System.Web.Services;
using Newtonsoft.Json;
using Sitecore;
using Sitecore.Jobs;
using Sitecore.SecurityModel;
using Sitecore.Shell.Client.Applications.Marketing.Utilities.DeployMarketingDefinitions;

[WebService(Namespace = "http://tempuri.org/")]
[WebServiceBinding(ConformsTo = WsiProfiles.BasicProfile1_1)]
[ToolboxItem(false)]
public class SimpleInstallScriptsProxy : WebService
{
    [WebMethod(Description = "Deploys Marketing Definitions")]
    public void DeployMarketingDefinitions()
    {
        JobManager.Start(new JobOptions("DeployMarketingDefinitions", "SimpleInstallScripts", "shell", this, "DeployMarketingDefinitionsInternal"));
    }

    [UsedImplicitly]
    private void DeployMarketingDefinitionsInternal()
    {
        var controller = new DeployMarketingDefinitionsController();
        var definitionTypes = new List<string>
        {
            "automationplans", 
            "campaigns",
            "events",
            "funnels",
            "goals",
            "marketingassets",
            "outcomes",
            "pageevents",
            "profiles",
            "segments"
        };

        var definitionTypesJson = JsonConvert.SerializeObject(definitionTypes);

        using (new SecurityDisabler())
        {
            var x = controller.DeployDefinitions(definitionTypesJson, true).Result;
        }
    }
}