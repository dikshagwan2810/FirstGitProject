#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRM.profile
#Requires -Modules AzureAD
#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script getting Global Admin account details from Azure Subscriptions

.DESCRIPTION
    This script gets details of all Global Admin accounts in all relevant Azure subscriptions.
    This runbook makes use of automation credential asset AzureADCredentials. Please ensure this credential has enough privileges for operation
    To be run on Hybrid Runbook Worker only

.INPUTS
    AzureAdCredentials => Credentials with sufficient privileges to fetch required details after connecting to AzureAD

.OUTPUTS
    CSV file with details for all roles and their members including global admin accounts

.EXAMPLE
    .\Get-GlobalAdminAccDetails.ps1

.NOTES
                          
    Author: Austin Palakunnel, Brijesh Shah     
    Company: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 13 June 2017
    Version: 1.0
#>


#Avoid the use of Owner or Global Administrator accounts
try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    $AzureAdCred = Get-AutomationPSCredential -Name "AzureADCredentials"
    $UserName = $AzureAdCred.UserName
    $SecurePassword = $AzureAdCred.Password
    $TempCreds = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)    
    
    $ContainerName = "reports"

    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")
    $SubscriptionId = $SubscriptionIDs[0]
    
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections
    Write-Verbose -Message "Connect to customer subscription"
    $CustomerContext = Set-AzureRmContext -SubscriptionId "$SubscriptionId" 
    
    Connect-AzureAD -Credential $TempCreds 
    [string]$CurrentDate = Get-Date -Format "dd-MM-yyyy"
    $CurrentDate = $CurrentDate.Replace("-","/")
    
    $RoleMembersDetail = @()
    $RoleInfo = Get-AzureADDirectoryRole | Select-Object -Property ObjectId, DisplayName
    foreach($Role in $RoleInfo)
    {
        $RoleMemberDetail = Get-AzureADDirectoryRoleMember -ObjectId $Role.ObjectId | Select-Object -Property DisplayName, UserPrincipalName
        foreach($RoleMember in $RoleMemberDetail)
        {
            $RoleMember | Add-Member -MemberType NoteProperty -Name "CurrentDate" -Value "$CurrentDate"
            $RoleMember | Add-Member -MemberType NoteProperty -Name "RoleDisplayName" -Value "$($Role.DisplayName)"
            $RoleMember | Add-Member -MemberType NoteProperty -Name "RoleDescription" -Value "$($Role.Description)"
        }
        $RoleMembersDetail += $RoleMemberDetail
    }

    $ManagementContext = Connect-AtosManagementSubscription

    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.Name -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -ErrorAction SilentlyContinue
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Verbose -Message "Container does not exist. Creating new Container for reporting..."
    }
    else
    {
        Write-Verbose -Message "Reporting Container already exists."
    }
    $CsvOutput = Get-AzureStorageBlobContent -Blob "RoleMembersDetail.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\RoleMembersDetail.csv" -Force -ErrorAction SilentlyContinue 
    if($null -ne $RoleMembersDetail)
    {
        $RoleMembersDetail | Export-Csv -Path "C:\RoleMembersDetail.csv" -Force -NoTypeInformation -Append
        Set-AzureStorageBlobContent -Context $StorageContext -Container "$ContainerName" -Blob "RoleMembersDetail.csv" -File "C:\RoleMembersDetail.csv" -Force
        Write-Verbose -Message "Write to files in storage account successful"
    }
    else
    {
        Write-Verbose -Message "No update to files required"
    }
    if(Test-Path -Path "C:\RoleMembersDetail.csv")
    {
        Remove-Item -Path "c:\RoleMembersDetail.csv" -Force 
    }
    Disconnect-AzureAD 
}
catch
{
    throw "$_"
}