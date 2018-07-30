#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRM.Profile
#Requires -Modules AzureRM.Insights
#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script getting details of automation account activities log 

.DESCRIPTION
    This script gets details of accounts to generate activities in Azure Automation.
    To be run on Hybrid Runbook Worker only

.INPUTS
    AutomationAccount => Mandatory parameter to add Automation Account name
    
.OUTPUTS
    CSV file with details of Automation account activity . The file will also be exported to storage account in the same resource group as the automation account

.EXAMPLE
    .\Get-AutomationAccActivity.ps1

.NOTES
                          
    Author: Brijesh Shah     
    Company: Atos
    Email: brijesh.shah@atos.net
    Created: 07 September 2017
    Version: 1.0
#>
param(
    [Parameter(Mandatory=$true)]
    $AutomationAccount
)
try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    $ContainerName = "reports"

    [string]$CurrentTime = Get-Date -Format "dd-MM-yyyy"
    $CurrentTime = $CurrentTime.Replace("-","/")
    $AutomationActivities = Get-AzureRmLog -StartTime (Get-Date).AddDays(-1) | Where-Object {($_.Authorization.scope -match $AutomationAccount) -and ($_.Authorization.Action -like "Microsoft.Automation/automationAccounts/*") -and ($_.Properties -notlike "")} | Select-Object @{Label='Operation name';Expression={$_.Authorization.Action}}, @{Label='Status';Expression={$_.Properties.Content.statusCode}}, @{Label='Category';Expression={$_.Category.Value}}, @{Label='Time';Expression={$_.EventTimestamp}}, SubscriptionId, @{Label='Event initiated by';Expression={$_.Caller}}, @{Label='Resource type';Expression={$_.OperationName.Substring(0,$_.OperationName.LastIndexOf('/'))}}, @{Label='Resource group';Expression={$Runbook.ResourceGroup}}, @{Label='Resource';Expression={$_.Authorization.Scope}}
        
    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.Name -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -ErrorAction SilentlyContinue    
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Verbose -Message "Container does not exist. Creating new Container $ContainerName for reporting..."
    }
    else
    {
        Write-Verbose -Message "Reporting Container already exists."
    }
    $CsvOutput = Get-AzureStorageBlobContent -Blob "AutomationAccActivityLog.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\AutomationAccActivityLog.csv" -Force -ErrorAction SilentlyContinue 
    if($null -ne $AutomationActivities)
    {
        $AutomationActivities | Export-Csv -Path "C:\AutomationAccActivityLog.csv" -Force -NoTypeInformation -Append
        Set-AzureStorageBlobContent -Context $StorageContext -Container "$ContainerName" -Blob "AutomationAccActivityLog.csv" -File "C:\AutomationAccActivityLog.csv" -Force | Out-Null
        Write-Verbose -Message "Write to files in storage account successful"
    }
    else
    {
        Write-Verbose -Message "No update to files required"
    }
    if(Test-Path -Path "C:\AutomationAccActivityLog.csv")
    {
        Remove-Item -Path "c:\AutomationAccActivityLog.csv" -Force
    }
}
catch
{
    throw "$_"
}