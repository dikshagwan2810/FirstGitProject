#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script to gather capacity limits of Microsoft resource providers from Azure portal

.DESCRIPTION
    This script collects information about Microsoft resource providers and their Usage, Default Limit per subscription per region. It creates CSV files for each subscription and stores it in local machine directory.
    Prerequisites: The script runs in Hybrid Runbook Worker which is an Azure VM with Atos.RunbookAutomation module and certificates depending on connection assests within the automation account for the customer resource group.
    Follow the document MSD-GAD-N225 OWI - MPC Azure - Automation Hybrid Runbook Workers.docx within SharePoint > Architecture Repository > OWI to install certificates.
    Create a schedule on the script to be run daily and add Hybrid Runbook Worker group name
    To be run on Hybrid Runbook Worker only

.INPUTS

.OUTPUTS
    CSV files for every customer subscription

.EXAMPLE
    .\Get-QuotaInfo.ps1

.NOTES
                          
    Author: Austin Palakunnel, Brijesh Shah     
    Company: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 16 May 2017
    Version: 1.0
#>

try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    
    $ContainerName = "reports"
    
    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")
    
    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.Name -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue 
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Output -Message "Container does not exist. Creating new Container $ContainerName for reporting..."
    }

    if(-not (Test-Path -Path "C:\SubscriptionQuotas\Temp"))
    {
        Write-Output "Creating new temporary directory for updating file..."
        New-Item -ItemType Directory -Path "C:\SubscriptionQuotas\Temp" | Out-Null
        Write-Output "Directory created"
    }

    [string]$CurrentDateAndTime = Get-Date -Format "dd-MM-yyyy"
  
    $count=1
    foreach($SubscriptionID in $SubscriptionIDs)
    {
        Get-AzureStorageBlobContent -Blob "Quotas_sub$($count).csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\SubscriptionQuotas\Temp\Quotas_sub$($count).csv" -Force -ErrorAction SilentlyContinue 
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionID -Connections $Runbook.Connections
        Write-Output -InputObject "Connect to customer subscription"
        Set-AzureRmContext -SubscriptionId "$SubscriptionID"
        $Resources = Get-AzureRmResource | Where-Object{(($_.ResourceType -like "Microsoft.Compute/*") -or ($_.ResourceType -like "Microsoft.Network/*")) -and ($_.Name -inotlike "Microsoft.Storage/storageaccounts")}
        $Regions = @()
        $Regions = $Resources | Select-Object -ExpandProperty Location -unique 
        $Regions1 = $Regions | Where-Object -FilterScript {$_ -inotlike "global"}
        $Regions  = $Regions1  
        
        $SubPrefix = "sub$count"
        $properties = @()
        $FileName = "C:\SubscriptionQuotas\Temp\Quotas_$($SubPrefix).csv"
        
        foreach($Region in $Regions)
        {
            $tempArray1 = Get-AzureRmVmUsage -Location $Region
            foreach( $row in $tempArray1 )
            {
                $tempArray2 = @{
                "Name" = $row.Name.LocalizedValue
                "Limit" = $row.Limit
                "CurrentValue" = $row.CurrentValue
                "Region" = $Region
                "CurrentDate" = $CurrentDateAndTime
                }
            $properties += New-object psobject -property $tempArray2
            }
            
            $tempArray3 = Get-AzureRmNetworkUsage -Location "$Region"
            foreach( $row in $tempArray3 )
            {
                $tempArray4 = @{
                "Name" = $row.Name.LocalizedValue
                "Limit" = $row.Limit
                "CurrentValue" = $row.CurrentValue
                "Region" = $Region
                "CurrentDate" = $CurrentDateAndTime
                }
            $properties += New-object psobject -property $tempArray4
            }
        }
        
        $tempArray5 = Get-AzureRmStorageUsage
        $tempArray6 = @{
            "Name" = $tempArray5.Name
            "Limit" = $tempArray5.Limit
            "CurrentValue" = $tempArray5.CurrentValue
            "Region" = "Global"
            "CurrentDate" = $CurrentDateAndTime
            }
        $properties += New-object psobject -property $tempArray6

        $properties | Export-Csv -Path "$FileName" -Delimiter ',' -NoType -Append
        $count++
    }
    $ManagementContext = Connect-AtosManagementSubscription

    If ($null -eq $ContainerTest)
    {
        Write-Verbose -Message "Couldn't find container. Creating new container $ContainerName..."
        New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission Blob | Out-Null
    }
    else
    {
        Write-Verbose -Message "Reporting Container already exists."
    }
    
    $count = 1
    foreach($SubscriptionID in $SubscriptionIDs)
    {
        Set-AzureStorageBlobContent -Context $StorageContext -Container $ContainerName -Blob "Quotas_sub$($count).csv" -File "C:\SubscriptionQuotas\Temp\Quotas_sub$($count).csv" -Force  | Out-Null
        $count++
    }
    Write-Output -InputObject "Files updated in storage account."
    Remove-Item -Path "C:\SubscriptionQuotas\Temp\*.csv" -Force -Recurse
}
catch
{
    throw "$_"
}