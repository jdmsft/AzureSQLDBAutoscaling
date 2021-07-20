# Azure SQL Database Single DB Autoscaling

## Components

* Azure Automation runbook to manage Autoscale for Azure SQL Database Single DB
* Azure Alert payload (as reference for manual firing)
* Minimal Azure Alert code (CAS) to manually firing an Alert
* PowerShell code to manually firing an Alert and thus the upscale operation (see below)

### Azure Alert payload

Below an Azure alert payload based on CAS (Common Alert Schema):

````json
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "/subscriptions/<subscription ID>/providers/Microsoft.AlertsManagement/alerts/b9569717-bc32-442f-add5-83a997729330",
      "alertRule": "WCUS-R2-Gen2",
      "severity": "Sev3",
      "signalType": "Metric",
      "monitorCondition": "Resolved",
      "monitoringService": "Platform",
      "alertTargetIDs": [
        "/subscriptions/<subscription ID>/resourcegroups/<rgName>/providers/microsoft.sql/servers/singledb/databases/singledb"
            ],
            "configurationItems": [
                "singledb"
            ],
      "originAlertId": "3f2d4487-b0fc-4125-8bd5-7ad17384221e_PipeLineAlertRG_microsoft.insights_metricAlerts_WCUS-R2-Gen2_-117781227",
      "firedDateTime": "2019-03-22T13:58:24.3713213Z",
      "resolvedDateTime": "2019-03-22T14:03:16.2246313Z",
      "description": "",
      "essentialsVersion": "1.0",
      "alertContextVersion": "1.0"
    },
    "alertContext": {
      "properties": null,
      "conditionType": "MultipleResourceMultipleMetricCriteria",
            "condition": {
                "windowSize": "PT1M",
                "allOf": [
                    {
                        "metricName": "cpu_percent",
                        "metricNamespace": "MICROSOFT.SQL/SERVERS/DATABASES",
                        "operator": "GreaterThan",
                        "threshold": "1",
                        "timeAggregation": "Average",
                        "dimensions": [],
                        "metricValue": 0.0,
                        "webTestName": null
                    }
                ]
    }
  }
}
````

### Azure Automation Runbook

#### Prerequisites

* **Az.Accounts** PowerShell module
* **Az.Sql** PowerShell module
* Azure Automation Connection (with rights to perform scaling action against Azure SQL Database)
* Azure Automation Certificate

#### Webhook data (from Azure Alert)

The runbook use only these following properties from the alert webhook data:

* schemaId
* data.essentials.alertTargetIds
* data.essentials.monitorCondition

#### Some considerations

* This runbook only use the first alert target received from the webhook data.
* This runbook only manage scale up action at this time *(I will update the runbook to support Scale Down later if I have time)*.
* If the alert that triggered the runbook is ***Activated*** or ***Fired***, it means we want to autoscale the database.
* If the alert that triggered the runbook is ***Resolved***, the runbook will be triggered again but because the status will be ***Resolved***, no autoscaling will happen.
* Because Azure SQL tiers cannot be obtained programatically, we need to hardcode them in the runbook.
* The runbook support the DTU tier and the vCore provisioned compute tiers, on Generation 4 and 5 and for both General Purpose and Business Critical tiers.
* With information provided by the WebhookData, the runbook determine the next tier that the database should be scaled to.

## How to use it

* Import this runbook into Azure Automation account.
* Create an Azure Alert (e.g. CPU percentage 80%) targeting the Azure SQL Database Single DB and calling the Automation runbook.

## How to simulate it

### Option 1 : Using Azure Alert

* Import this runbook into Azure Automation account.
* Create an Azure Alert (e.g. CPU percentage 80%) targeting the Azure SQL Database Single DB and calling the Automation runbook.
* Request SQL database (using stress tool for instance) to increase compute consumption.
* Validate automatic Azure SQL Database Single DB autoscale.

### Option 2 : Simulate a fired Azure Alert (via Azure Automation Webhook)

Because we can't trigger (fire) manually an Azure Alert to run the runbook, you should follow these steps:

* Add a webhook to the Automation runbook.
* Create/Edit the Azure Alert shortened payload below:

````json
{
    "schemaId": "azureMonitorCommonAlertSchema",
    "data": {
        "essentials": {
            "monitorCondition": "Fired",
            "alertTargetIDs": [
                "/subscriptions/<subId>/resourceGroups/<rgName>/providers/Microsoft.Sql/servers/<sqlServerName>/databases/<sqlServerDb>"
            ]
        }
    }
}
````

* Call the webhook with the Azure Alert shortened payload edited previously as webhook data:

````powershell
$WebHookData = Get-Content "Alert.json"
$WebhookEndpoint = '<webhookUrl>'
iwr -Method Post -Uri $WebhookEndpoint -Body $WebHookData
````

## Acronyms

* BOL = Books Online
* CAS = Common Alert Schema

## Credits

Adapted from [juliocaledron](https://techcommunity.microsoft.com/t5/azure-database-support-blog/how-to-auto-scale-azure-sql-databases/ba-p/2235441)