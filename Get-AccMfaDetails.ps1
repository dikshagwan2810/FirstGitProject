#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRM.profile
#Requires -Modules MSOnline
#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script getting details of accounts to check whether all accounts have Multi-factor authentication

.DESCRIPTION
    This script gets details of accounts to check whether all accounts have Multi-factor authentication in all relevant Azure subscriptions.
    This runbook makes use of automation credential asset AzureADCredentials. Please ensure this credential has enough privileges for operation.
    To be run on Hybrid Runbook Worker only

.INPUTS
    AzureAdCredentials => Credentials with sufficient privileges to fetch required details after connecting to MSOLservice

.OUTPUTS
    CSV file with details of MFA enabled or not on user accounts. The file will also be exported to storage account in the same resource group as the automation account

.EXAMPLE
    .\Get-AccMfaDetails.ps1

.NOTES
                          
    Author: Austin Palakunnel, Brijesh Shah     
    Company: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 13 June 2017
    Version: 1.0
#>


#Ensure multi-factor authentication (MFA) is enabled for users accessing the ARM portal
#Currently not supported in AzureAD v2
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
    Write-verbose -Message "Connect to customer subscription"
    $CustomerContext = Set-AzureRmContext -SubscriptionId "$SubscriptionId" 
    
    Connect-MsolService -Credential $TempCreds 
    [string]$CurrentTime = Get-Date -Format "dd-MM-yyyy"
    $CurrentTime = $CurrentTime.Replace("-","/")
    $AccMfaDetails = Get-MsolUser -TenantId $CustomerContext.Tenant.TenantId  |  Select-Object -Property UserPrincipalName, DisplayName, @{Label="MfaEnabled";Expression={$_.StrongAuthenticationMethods.Count -ne 0}}
    Foreach($AccMfaDetail in $AccMfaDetails)
    {
        $AccMfaDetail | Add-Member -MemberType NoteProperty -Name "DateTime" -Value "$CurrentTime"
    }

    $ManagementContext = Connect-AtosManagementSubscription

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
    $CsvOutput = Get-AzureStorageBlobContent -Blob "MFALicense.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\MFALicense.csv" -Force -ErrorAction SilentlyContinue 
    if($null -ne $AccMfaDetails)
    {
        $AccMfaDetails | Export-Csv -Path "C:\MFALicense.csv" -Force -NoTypeInformation -Append
        Set-AzureStorageBlobContent -Context $StorageContext -Container "$ContainerName" -Blob "MFALicense.csv" -File "C:\MFALicense.csv" -Force | Out-Null
        Write-Verbose -Message "Write to files in storage account successful"
    }
    else
    {
        Write-Verbose -Message "No update to files required"
    }
    if(Test-Path -Path "C:\MFALicense.csv")
    {
        Remove-Item -Path "c:\MFALicense.csv" -Force
    }
}
catch
{
    throw "$_"
}