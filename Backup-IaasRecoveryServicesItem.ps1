#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Backs-up a VM outside of it's normal schedule

    .DESCRIPTION
    This script will initiate the backup of a VM outside of its normal backup schedule.
    The script will return SUCCESS once the backup has started. To watch the progress of
    the backup you can use the returned JobID and ActivityID to query Azure.

    PLEASE NOTE: This will only work on a VM that has already been enabled for scheduled backups.

    .NOTES
    Author:     Russell Pitcher
    Company:    Atos
    Email:      russell.pitcher@atos.net
    Created:    2017-01-20
    Updated:    2017-04-06
    Version:    1.1
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The name of the VM to back up
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$false)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$false)]
    [String]
    $ConfigurationItemId
)

try {
    # Validate parameters (PowerShell parameter validation is not available in Azure)
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Parameter SubscriptionId is Null or Empty"}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Parameter VirtualMachineResourceGroupName is Null or Empty"}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Parameter VirtualMachineName is Null or Empty"}

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections


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

    Write-Verbose "Retrieving Recovery Services container"
    $BackupVault = Get-AzureRmRecoveryServicesVault -Name $VaultName
    if ($BackupVault -eq $null) {
        throw "Cannot retrieve backup vault '${VaultName}'"
    }

    Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault
    $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
    $backupItem = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer -WorkloadType "AzureVM"
    if ($backupItem -eq $null) {
        throw "Cannot retrieve backupItem for VM ${VirtualMachineName}.  Please ensure that backup has been enabled for this item."
    }

    Write-Verbose "Starting backup"
    $BackupJob = Backup-AzureRmRecoveryServicesBackupItem -Item $backupItem

    if ($BackupJob) {
        $status = "SUCCESS"
        $returnMessage =  "Backup job accepted and started successfully`n"
        $returnMessage += "ActivityID = $($BackupJob.ActivityId)`n"
        $returnMessage += "JobID = $($BackupJob.JobId)"


        # Connect to the management subscription
        Write-Verbose "Connecting to default subscription"
        $ManagementContext = Connect-AtosManagementSubscription

        $RunbookName = "Wait-IaasBackupJob"
        $RunbookParameters = @{
            SubscriptionId = $SubscriptionId
            VirtualMachineName = $VirtualMachineName
            VirtualMachineResourceGroupName = $VirtualMachineResourceGroupName
            BackupJobId = $BackupJob.JobId
            RequestorUserAccount = $RequestorUserAccount
            ConfigurationItemId = $ConfigurationItemId
        }

        Write-Verbose "Starting ${RunbookName} runbook with the following parameters:"
        $RunbookParameters.GetEnumerator() | ForEach-Object {
            Write-Verbose "  - $($_.Key)  =  $($_.Value)"
        }

        $BackupWatch = Start-AzureRmAutomationRunbook -Name $RunbookName -Parameters $RunbookParameters -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount
        Write-Verbose "VM Backup has been initiated and will be watched under Runbook Job '$($BackupWatch.JobID)'"

    } else {
        $status = "FAILURE"
        $returnMessage = "Error - Backup job failed to start."
    }
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage