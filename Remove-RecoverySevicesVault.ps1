Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VaultName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VaultResourceGroupName,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $ConfigurationItemId
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

    # Code that must be run under the CUSTOMER context goes here

    $Vault = Get-AzureRmRecoveryServicesVault -Name $VaultName -ResourceGroupName $VaultResourceGroupName
    Set-AzureRmRecoveryServicesVaultContext -Vault $Vault
    $Containers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType 'AzureVM' -Status 'Registered'

    forEach ($Container in $Containers) {
        Write-Verbose "Disabling protection for $($Container.ResourceGroupName)\$($Container.FriendlyName)"
        $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $Container -WorkloadType 'AzureVM'
        Disable-AzureRmRecoveryServicesBackupProtection -Item $BackupItem -RemoveRecoveryPoints -Confirm:$false -Force
    }

    Write-Verbose "Deleting Recovery Services Vault '$($Vault.Name)'"
    $RemoveResults = Remove-AzureRmRecoveryServicesVault -Vault $vault
    if ($RemoveResults.Response -match 'has been deleted')
        $returnStatus = 'SUCCESS'
        $returnMessage = $RemoveResults.Response
    } else {
        $returnStatus = 'FAILURE'
        $returnMessage = $RemoveResults.Response
    }

} catch {
    $returnStatus = 'FAILURE'
    $returnMessage = "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage