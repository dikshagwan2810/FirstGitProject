#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    One-line summary

    .DESCRIPTION
    Detailed description

    .OUTPUTS
    Outputs, if any

    .NOTES
    Author:     Russell Pitcher
    Company:    Atos
    Email:      russell.pitcher@atos.net
    Created:    2017-09-19
    Updated:    2017-09-19
    Version:    0.1
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory = $true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory = $true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory = $true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineResourceGroupName,

    # The end of the range to look for restore points
    [Parameter(Mandatory = $true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $BackupJobId,

    # The account of the user who requested this operation
    [Parameter(Mandatory = $false)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory = $false)]
    [String]
    $ConfigurationItemId
)

# Everything wrapped in a try/catch to ensure SNow-compatible output
try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections | Out-Null

    ## Get backup vault from atosMaintenanceString2 tag
    Write-Verbose "Getting Recovery Services vault from VM tags"
    $VirtualMachine = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    if ($VirtualMachine -eq $null) {
        throw "Cannot find VM ${VirtualMachineName} in resource group ${VirtualMachineResourceGroupName}"
    }
    if ($VirtualMachine.Tags.atosMaintenanceString2 -eq $null) {
        throw "Cannot find vault to use - Cannot find atosMaintenanceString2 tag!"
    } else {
        $atosObject = $VirtualMachine.Tags.atosMaintenanceString2 | ConvertFrom-JSON
        if ($atosObject.RSVault -eq $null) {
            throw "Cannot find vault to use - RSVault value missing from atosMaintenanceString2 tag!"
        } else {
            $VaultName = $atosObject.RSVault
        }
    }

    Write-Verbose "Setting Vault context"
    $BackupVault = Get-AzureRmRecoveryServicesVault -Name $VaultName
    if ($BackupVault -eq $null) {
        throw "Cannot retrieve backup vault '${VaultName}'"
    }

    Write-Verbose "Setting vault context"
    Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault

    Write-Verbose "Getting backup job from Id"
    $BackupJob = Get-AzureRmRecoveryServicesBackupJob -JobId $BackupJobId
    if ($null -eq $BackupJob) {
        throw "Could not find a job with Id '${BackupJobId}'"
    }

    Write-Verbose "Waiting for backup job to complete"
    $BackupJob = Wait-AzureRmRecoveryServicesBackupJob -Job $BackupJob
    switch ($BackupJob.Status) {
        'Completed' {
            Write-Verbose "Backup job has completed"
        }
        Default {
            throw "Backup job '${BackupJobId}' has failed to complete with status: $($BackupJob.Status)"
        }
    }

    Write-Verbose "Retrieving backup container"
    $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
    Write-Verbose "Retrieving backup items"
    $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer -WorkloadType "AzureVM"
    if ($BackupItem -eq $null) {
        throw "Cannot retrieve backupItem for VM ${VirtualMachineName}. Please ensure that backup has been enabled for this item."
    }

    Write-Verbose "Retrieving Recovery points"
    $RecoveryPoints = Get-AzureRmRecoveryServicesBackupRecoveryPoint -Item $BackupItem -StartDate $BackupJob.StartTime

    # Reconnect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    # TODO: Send-EmailToCustomer

    $SnowResult = Send-RecoveryPointToSnow -SubscriptionId $SubscriptionId -VirtualMachine $VirtualMachine -RecoveryVault $BackupVault -RecoveryPoint $RecoveryPoints[0]

    if ($SnowResult[0] -eq 'SUCCESS') {
        $returnStatus = 'SUCCESS'
        $returnMessage = "Backup completed successfuly and Snow updated: $($SnowResult[1])"
    } else {
        Write-Verbose "Snow Recovery Point update result:"
        $SnowResult | ForEach-Object {Write-Verbose " - $($_.ToString())"}
        $returnStatus = 'FAILURE'
        $returnMessage = "Failed to update Snow with recovery point details. $($SnowResult[1])"
    }


} catch {
    $returnStatus = 'FAILURE'
    Write-Verbose "FATAL ERROR: $($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
    $returnMessage = "$($_.ToString())"
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage