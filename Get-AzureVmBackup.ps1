#Requires -Version 5.0
#Requires -RunAsAdministrator
#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRm.RecoveryServices

<#
.SYNOPSIS
    Script to get details of all VMs in Backup in Customer subscriptions

.DESCRIPTION
    This script collects results for all VMs that have a backup in any of the Backup Vaults in the customer subscriptions
    It creates csv file with the consolidated list.
    Create a schedule on the script to be run daily and provide all the mandatory parameters to the script.
    To be run on Hybrid Runbook Worker only

.INPUTS

.OUTPUTS
    CSV file having details of all VMs havign Backup

.EXAMPLE
    .\Get-AzureVmBackup.ps1 

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

    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.StorageAccountName -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName -Name $StorageAccount.StorageAccountName
    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $StorageAccountKey[0].Value
    
    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")

    $OutputArray = @()

    foreach($SubscriptionID in $SubscriptionIDs)
    {
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionID -Connections $Runbook.Connections        
        $CustomerContext = Set-AzureRmContext -SubscriptionId "$SubscriptionID" 
        $Vaults = Get-AzureRmRecoveryServicesVault     
        foreach($Vault in $Vaults)
        {
            $Vault | Set-AzureRmRecoveryServicesVaultContext | Out-Null
                
            $OutputArray += Get-AzureRmRecoveryServicesBackupJob -BackupManagementType AzureVM -Operation Backup | Select-Object  @{l="VaultName";e={$Vault.Name}}, WorkloadName, Operation, Status, StartTime, EndTime, JobID
        }
    }

    $ManagementContext = Connect-AtosManagementSubscription
    
    if(Test-Path -Path "C:\Temp\BackupVMsInfo.csv") 
    {
        ##Clearing files for new data
        Remove-Item -Path "C:\Temp\BackupVMsInfo.csv" | Out-Null
    }

    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue
    If ($null -eq $ContainerTest)
    {
        Write-Verbose -Message "Couldn't find container. Creating new container $ContainerName..."
        New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission Blob | Out-Null         
    }
    if(-not (Test-Path -Path "C:\Temp"))
    {
        Write-Output "Creating new temporary directory for updating file..."
        New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
        Write-Output "Directory created"
    }
    
    # Download the file from storage account to which data has to be updated
    Write-Verbose -Message "Downloading file so that new data can be appended..."        
    Get-AzureStorageBlobContent -Blob "BackupVMsInfo.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\Temp\BackupVMsInfo.csv" -Force -ErrorAction SilentlyContinue | Out-Null

    $OutputArray | Export-Csv -Path "C:\Temp\BackupVMsInfo.csv" -Append -NoTypeInformation -Force 

    if(Test-Path -Path "C:\Temp\BackupVMsInfo.csv")
    {
        Set-AzureStorageBlobContent -Container $ContainerName -Context $StorageContext -File "C:\Temp\BackupVMsInfo.csv" -Blob "BackupVMsInfo.csv" -Force | Out-Null
        Remove-Item -Path "C:\Temp\BackupVMsInfo.csv" -Force | Out-Null
    }
}
catch
{
    throw "$_"
}