#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRM.profile
#Requires -Modules AzureADUtilsModule
#Requires -Modules AzureADPreview
#Requires -Modules AzureAutomationAuthoringToolkit
#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script to get Azure AD Audit Logs

.DESCRIPTION
    This script collects results from Azure AD Audit logs.
    It creates csv file for the query and updates the file in storage account with the results
    Create a schedule on the script to be run daily and provide all the mandatory parameters to the script.
    To be run on Hybrid Runbook Worker only

.INPUTS

.OUTPUTS
    CSV file with details of Azure AD Audit logs . The file will also be exported to storage account

.EXAMPLE
    .\Get-AzureADAuditReport.ps1

.NOTES
                          
    Author: Austin Palakunnel, Brijesh Shah     
    Company: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 07 September 2017
    Version: 1.0
#>

try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    $ConnectionName = (Get-AzureRmAutomationConnection -AutomationAccountName $Runbook.AutomationAccount -ResourceGroupName $Runbook.ResourceGroup -ConnectionTypeName "AzureServicePrincipal") | Where-Object {$_.Name -notlike "DefaultRunAsConnection"} | Select-Object -First 1 -ExpandProperty Name
    $ClientID = (Get-AutomationConnection -Name $ConnectionName).ApplicationId
    $CertificateThumbprint = (Get-AutomationConnection -Name $ConnectionName).CertificateThumbprint
    
    $loginURL       = "https://login.windows.net/"
    $resource       = "https://graph.windows.net"
    
    $ContainerName = "reports"

    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")
    $SubscriptionId = $SubscriptionIDs[0]
    
    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.Name -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue 
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Output -Message "Container does not exist. Creating new Container $ContainerName for reporting..."
    }

    if(-not (Test-Path -Path "C:\Temp"))
    {
        Write-Output "Creating new temporary directory for updating file..."
        New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
        Write-Output "Directory created"
    }
    
    Get-AzureStorageBlobContent -Blob "AzureADAuditLogs.csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\Temp\AzureADAuditLogs.csv" -Force -ErrorAction SilentlyContinue 
    
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections
    Write-Output "Connect to customer subscription"
    Set-AzureRmContext -SubscriptionId "$SubscriptionId"
    $TenantId = (Get-AzureRmSubscription).TenantId

    Connect-AzureAD -TenantId $TenantId -ApplicationId $ClientID -CertificateThumbprint $CertificateThumbprint
    $tenantdomain = (Get-AzureADDomain) | Where-Object {$_.IsDefault -eq "True"} | select -ExpandProperty Name

    $CurrentDate = "{0:s}" -f (get-date).AddDays(-1) + "Z"

    $accessToken = Get-AzureADGraphAPIAccessTokenFromCert -TenantDomain $tenantdomain -ClientId $ClientID -Certificate (dir Cert:\LocalMachine\My\$CertificateThumbprint)
    if ($accessToken -ne $null)
    {
        $myReport = Invoke-AzureADGraphAPIQuery -TenantDomain $tenantdomain -AccessToken $accessToken -GraphQuery "/activities/audit?api-version=beta&`$filter=activityDate ge $CurrentDate" 
        $Output = @()
        foreach($record in $myReport)
        {
            $Properties = @{
                Date = $record.activityDate
                Actor = $record.actor.name
                Activity = $record.activity
            }
            if($Properties["Actor"] -like "" -or $null -eq $Properties["Actor"])
            {
                $Properties["Actor"] = $record.actor.userPrincipalName
            }
            if($Properties["Actor"] -like "" -or $null -eq $Properties["Actor"])
            {
                $Properties["Actor"] = $record.actor.objectId
            }
            $TargetsString = ""
                        foreach($Target in $record.targets)
            {
                $TempName  = ""
                if($Target.name -like "" -or $null -eq $Target.name)
                {
                    $TempName = $Target.userPrincipalName
                }
                else
                {
                    $TempName = $Target.name
                }
                $Temp = $Target.targetResourceType + " : " + $TempName
                if($TargetsString -like "")
                {
                    $TargetsString = $Temp
                }
                else
                {
                    $TargetsString = $TargetsString + ", $Temp"
                }
            }
            $Properties["Target"] = $TargetsString
            $Output += New-Object psobject -Property $Properties
        }
        Write-Output "Done with conversion..."
    }
    else 
    {
        Write-Output "ERROR: No Access Token"
    }    
        
    if($null -eq $myReport)
    {
        Write-Output "No update to files required"
    }
    else
    {
        $Output | Export-Csv -Path "C:\Temp\AzureADAuditLogs.csv" -Append -NoTypeInformation -Force
        $ManagementContext = Connect-AtosManagementSubscription
        Set-AzureStorageBlobContent -Context $StorageContext -Container $ContainerName -Blob "AzureADAuditLogs.csv" -File "C:\Temp\AzureADAuditLogs.csv" -Force  | Out-Null
        Write-Output -InputObject "Files updated in storage account."
        Remove-Item -Path "C:\Temp\AzureADAuditLogs.csv" -Recurse -Force | Out-Null
    }
}
catch
{
    throw "$_"
}