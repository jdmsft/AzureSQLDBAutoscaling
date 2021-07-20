# Required modules : Az.Accounts and Az.Sql
param
(
    [Parameter (Mandatory = $false)]
    [object] $WebhookData,
    [boolean] $ShowReceivedJson = $false
)

$RunbookVersion = '1.1.4'
$AutomationConnectionName = 'AzureRunAsConnection'

Write-Output "`nAzure SQL Database Single DB autoscaling v$RunbookVersion`n(c) 2021 JDMSFT. All right Reserved.`n"

If ($WebhookData)
{
    Write-Verbose "Webhook data received!"

    If ($ShowReceivedJson)
    {
        Write-Output "=========== Webhook data received (RequestBody) ==========="
        $WebhookData.RequestBody
        Write-Output "==========================================================="
    }

    # Get the data object from WebhookData
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

    # Validate the schema using CAS (released March 2019)
    $schemaId = $WebhookBody.schemaId
    Write-Verbose "schemaId: $schemaId"
    If ($schemaId -eq "azureMonitorCommonAlertSchema") 
    {
        $Essentials = [object] ($WebhookBody.data).essentials
        Write-Verbose $Essentials
        
        $alertTargetIdArray = (($Essentials.alertTargetIds)[0]).Split("/")
        $SubId = ($alertTargetIdArray)[2]
        $ResourceGroupName = ($alertTargetIdArray)[4]
        $ResourceType = ($alertTargetIdArray)[6] + "/" + ($alertTargetIdArray)[7]
        $ServerName = ($alertTargetIdArray)[8]
        $DatabaseName = ($alertTargetIdArray)[-1]
        $Status = $Essentials.monitorCondition
    }
    Else { Write-Error "The alert data schema - $schemaId - is not supported (Common Alert Schema required)." }

    # Trigger an upscale action
    If (($Status -eq "Activated") -or ($Status -eq "Fired"))
    {
        Write-Output "Alert Status : $Status"
        Write-Output "Alert Target: $(($Essentials.alertTargetIds)[0])"

        $DtuTiers = @('Basic', 'S0', 'S1', 'S2', 'S3', 'S4', 'S6', 'S7', 'S9', 'S12', 'P1', 'P2', 'P4', 'P6', 'P11', 'P15')
        $Gen4Cores = @('1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '16', '24')
        $Gen5Cores = @('2', '4', '6', '8', '10', '12', '14', '16', '18', '20', '24', '32', '40', '80')

        #region Azure Connector for Azure Automation
        Write-Verbose "Azure Connector for Azure Automation v1.4.0`n(c) 2020 - 2021 JDMSFT. All right Reserved."
        $ConnectorTimer = [system.diagnostics.stopwatch]::StartNew()
        Try
        {
            $AutomationConnection = Get-AutomationConnection -Name $AutomationConnectionName
            Connect-AzAccount `
                -ServicePrincipal `
                -TenantId $AutomationConnection.TenantId `
                -SubscriptionId $AutomationConnection.SubscriptionId `
                -ApplicationId $AutomationConnection.ApplicationId `
                -CertificateThumbprint $AutomationConnection.CertificateThumbprint `
                -SkipContextPopulation | Out-Null
        }
        Catch 
        {
            If (!$AutomationConnection) { $ErrorMessage = "Connection $AutomationConnectionName not found." ; throw $ErrorMessage } 
            Else { Write-Error $($_) ; throw "[$($_.InvocationInfo.ScriptLineNumber)] $($_.InvocationInfo.Line.TrimStart()) >> $($_)" }
        }
        $ConnectorTimer.Stop()
        Write-Verbose "Azure Connector for Azure Automation (Elapsed time : $($ConnectorTimer.Elapsed))"
        #endregion

        If ($AutomationConnection)
        {
            # Get Azure SQL Database details
            $currentDatabaseDetails = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -DatabaseName $DatabaseName -ServerName $ServerName

            # Upscale
            If (($currentDatabaseDetails.Edition -eq "Basic") -Or ($currentDatabaseDetails.Edition -eq "Standard") -Or ($currentDatabaseDetails.Edition -eq "Premium"))
            {
                Write-Output "Alert Target Database model : DTU"

                If ($currentDatabaseDetails.CurrentServiceObjectiveName -eq "P15") { Write-Output "DTU database is already at highest tier (P15). Suggestion is to move to Business Critical vCore model with 32+ vCores." } 
                Else 
                {
                    For ($i = 0; $i -lt $DtuTiers.length; $i++) 
                    {
                        If ($DtuTiers[$i].equals($currentDatabaseDetails.CurrentServiceObjectiveName)) 
                        {
                            Set-AzSqlDatabase -ResourceGroupName $ResourceGroupName -DatabaseName $DatabaseName -ServerName $ServerName -RequestedServiceObjectiveName $DtuTiers[$i + 1]
                            break
                        }
                    }
                }
            } 
            Else 
            {
                Write-Output "Alert Target Database model : vCore"

                $currentVcores = ""
                $currentTier = $currentDatabaseDetails.CurrentServiceObjectiveName.SubString(0, 8)
                $currentGeneration = $currentDatabaseDetails.CurrentServiceObjectiveName.SubString(6, 1)
                $coresArrayToBeUsed = ""

                Try { $currentVcores = $currentDatabaseDetails.CurrentServiceObjectiveName.SubString(8, 2) } Catch { $currentVcores = $currentDatabaseDetails.CurrentServiceObjectiveName.SubString(8, 1) }
            
                Write-Output $currentGeneration
                If ($currentGeneration -eq "5") { $coresArrayToBeUsed = $Gen5Cores } Else { $coresArrayToBeUsed = $Gen4Cores }
            
                If ($currentVcores -eq $coresArrayToBeUsed[$coresArrayToBeUsed.length]) { Write-Output "vCore database is already at highest number of cores. Suggestion is to optimize workload." } 
                Else
                {
                    For ($i = 0; $i -lt $coresArrayToBeUsed.length; $i++) 
                    {
                        If ($coresArrayToBeUsed[$i] -eq $currentVcores) 
                        {
                            $newvCoreCount = $coresArrayToBeUsed[$i + 1]
                            Set-AzSqlDatabase -ResourceGroupName $ResourceGroupName -DatabaseName $DatabaseName -ServerName $ServerName -RequestedServiceObjectiveName "$currentTier$newvCoreCount"
                            break
                        }
                    }
                }
            }
        }
    }
    Else { Write-Verbose "Skipping alert because is not Fired or Activated." }
}