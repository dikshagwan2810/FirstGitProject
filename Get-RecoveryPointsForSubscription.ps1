#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Returns all recovery points for all backup vaults in the supplied subscription

    .DESCRIPTION
    Outputs a list containing details of all AzureVM recovery points for all recovery vaults in the supplied subscription.

    .OUTPUTS
    Line1 = SUCCESS or FAILURE
    Subsequent lines = Recovery Point details or error details

    .NOTES
    Author:     Russell Pitcher
    Company:    Atos
    Email:      russell.pitcher@atos.net
    Created:    2017-08-21
    Updated:    2017-08-21
    Version:    0.1
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    [Parameter(Mandatory=$false)]
    [String][ValidateSet('AzureVM','AzureSQLDatabase')]
    $Containertype = 'AzureVM'
)

# Everything wrapped in a try/catch to ensure SNow-compatible output
try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    $BackupVaults = Get-AzureRmRecoveryServicesVault

    $AllRecoveryPoints = ForEach ($Vault in $BackupVaults) {
        Set-AzureRmRecoveryServicesVaultContext -Vault $Vault
        $namedContainers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType 'AzureVM' -Status 'Registered'
        ForEach ($Container in $namedContainers) {
            $BackupItems = Get-AzureRmRecoveryServicesBackupItem -Container $Container -WorkloadType "AzureVM"
            ForEach ($BackupItem in $BackupItems) {
                $RecoveryPoints = Get-AzureRmRecoveryServicesBackupRecoveryPoint -Item $BackupItem
                ForEach ($RecoveryPoint in $RecoveryPoints) {
                    [PSCustomObject]@{
                        VaultSubscription  = $Vault.SubscriptionId
                        VaultLocation      = $Vault.Location
                        VaultResourceGroup = $Vault.ResourceGroupName
                        VaultName          = $Vault.Name
                        VmResourceGroup    = $RecoveryPoint.ContainerName.Split(';')[-2]
                        VmName             = $RecoveryPoint.ContainerName.Split(';')[-1]
                        RecoveryPointID    = $RecoveryPoint.RecoveryPointID
                        RecoveryPointTime  = $RecoveryPoint.RecoveryPointTime.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
                        RecoveryPointType  = $RecoveryPoint.RecoveryPointType
                        ContainerType      = $RecoveryPoint.ContainerType
                    }
                }
            }
        }
    }

    # $returnStatus should be 'SUCCESS' or 'FAILURE'
    $returnStatus = 'SUCCESS'
    # $returnMessage can be either a simple string or an array of strings.
    $returnMessage = $AllRecoveryPoints
} catch {
    $returnStatus = 'FAILURE'
    $returnMessage = "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage