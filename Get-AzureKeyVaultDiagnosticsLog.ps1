#Requires -Version 5.0
#Requires -RunAsAdministrator
#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRm.OperationalInsights

<#
.SYNOPSIS
    Script to get Key Vault Analytics search query results from workspace in Azure

.DESCRIPTION
    This script collects results for Log Search queries from OMS workspace in the specified subscription and resource group.
    It creates csv file for each query and updates the files in storage account with the results
    Create a schedule on the script to be run daily and provide all the mandatory parameters to the script.
    To be run on Hybrid Runbook Worker only

.INPUTS

.OUTPUTS
    CSV file with details of the Key Vault Log Analytics search query

.EXAMPLE
    .\Get-AzureKeyVaultDiagnosticsLog

.NOTES
                          
    Author: Brijesh Shah     
    Company: Atos
    Email: brijesh.shah@atos.net
    Created: 10 October 2017
    Version: 1.0
#>

try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    
    $ContainerName = "reports"

    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")

    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.StorageAccountName -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName -Name $StorageAccount.StorageAccountName
    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue 
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Output -Message "Container does not exist. Creating new Container $ContainerName for reporting..."
    }
    
    $CsvOutput = Get-AzureStorageBlobContent -Blob "AzureKeyVaultDiagnosticsLogs.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\Temp\AzureKeyVaultDiagnosticsLogs.csv" -Force -ErrorAction SilentlyContinue 

    # Set query start search time to rounded 1 day interval start time
    $CurrentDateAndTime = [datetime]::Now    
    $EndDateAndTime = $CurrentDateAndTime.DateTime
    $StartDateAndTime = $CurrentDateAndTime.AddDays(-1)
    $EndDate = Get-Date -Date $EndDateAndTime -Format u
    $StartDate = Get-Date -Date $StartDateAndTime -Format u
    $StartTime = Get-Date

    foreach($SubscriptionID in $SubscriptionIDs)
    {
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionID -Connections $Runbook.Connections
        Write-Output -InputObject "Connect to customer subscription"
        Set-AzureRmContext -SubscriptionId "$SubscriptionID" | out-null

        $MPCASubId = $MPCAConfigurationFile.MPCAConfiguration.Subscriptions | where {$_.Id -like $SubscriptionId}
        #$SubscriptionId1 = $MPCASubId.Id.split(":")[0]
        $WorkspaceName1 = $MPCASubId.OMSWorkspaceName.split(":")[0]
        $OMSWorkspace = Get-AzureRmOperationalInsightsWorkspace | Where-Object {$_.Name -eq $WorkspaceName1}
        $ResourceGroupName1 = $OMSWorkspace.ResourceGroupName

        $workspaceId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName1/providers/microsoft.operationalinsights/workspaces/$WorkspaceName1"
        Write-Output $workspaceId
        $keyvaults = Get-AzureRmKeyVault | Where-Object -FilterScript {$_.ResourceId -like "/subscriptions/$SubscriptionID/*"} 
        $kv = $keyvaults.ResourceId
        Write-Output $kv
       
        # Enable Azure Diagnostics settings and send to Log Analytics
        foreach($ResourceId in $kv)
        {
            If ((Get-AzureRmDiagnosticSetting -ResourceId $ResourceId).logs.enabled -eq "True")
            {
                Write-Output "Diagnostics Logs is enabled on $ResourceId"
            }
            else
            {
                Set-AzureRmDiagnosticSetting -ResourceId $ResourceId -Enabled $true -WorkspaceId $workspaceId
                Write-Output "Set Diagnostics Logs on $ResourceId"
            }
        }

        # Set Log Analytics query
        $QueriesDetail=@()
        $QueriesDetail = @(
            [pscustomobject]@{
            "Query" = "Type = AzureDiagnostics ResourceType = VAULTS"
            }
        )
        
        if(-not (Test-Path -Path "C:\Temp"))
        {
            Write-Output "Creating new temporary directory for updating file..."
            New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
            Write-Output "Directory created"
        }
        
        foreach($Query in $QueriesDetail)
        {
            $Outfilename = "C:\Temp\AzureKeyVaultDiagnosticsLogs.csv"

            # Get Initial results
            $Results = Get-AzureRmOperationalInsightsSearchResults -WorkspaceName $WorkspaceName1 -ResourceGroupName $ResourceGroupName1 -Query $Query.Query -Start $StartDate -End $EndDate -Top 5000
            $elapsedTime = $(Get-Date) - $StartTime
            Write-Output "Elapsed: " $elapsedTime "Status: " $Results.Metadata.Status

            # Split and extract request Id
            $reqIdParts = $Results.Id.Split("|")
            $reqIdParts1 = $reqIdParts.Split("/")
            $reqId = $reqIdParts1[$reqIdParts1.Count -2]

            # Poll if pending
            while($Results.Metadata.Status -eq "Pending" -and $error.Count -eq 0) {
            $Results = Get-AzureRmOperationalInsightsSearchResults -WorkspaceName $WorkspaceName1 -ResourceGroupName $ResourceGroupName1 -Id $reqId
            $elapsedTime = $(Get-Date) - $StartTime
            Write-Output "Elapsed: " $elapsedTime "Status: " $Results.Metadata.Status
            }
    
            $CSV = @()
            foreach($Result in $Results.Value)
            {
                $CSV += $($Result.ToString() | ConvertFrom-Json)
            }
            if($null -ne $CSV)
            {
                $CSV | Export-Csv -Path $Outfilename -Append -NoTypeInformation -Force
            }
        }
    }    
    # Upload the local files to storage account
    Write-Output "Uploading files to storage account..."

    $ManagementContext = Connect-AtosManagementSubscription
    foreach($Query in $QueriesDetail)
    {
        if(Test-Path -Path "C:\Temp\AzureKeyVaultDiagnosticsLogs.csv")
            {
                Set-AzureStorageBlobContent -Container $ContainerName -Context $StorageContext -File "C:\Temp\AzureKeyVaultDiagnosticsLogs.csv" -Blob "AzureKeyVaultDiagnosticsLogs.csv" -Force | Out-Null
                Remove-Item -Path "C:\Temp\AzureKeyVaultDiagnosticsLogs.csv" -Force | Out-Null
            }
    }
    Write-Output "Upload complete"  
}
catch
{
    throw "$_"
}