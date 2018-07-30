#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Restores an existing IaaS VM from a backup

    .DESCRIPTION
    This script will restore an already existing IaaS VM from an earlier backup.  This runbook will select the most recent recovery point from the range specified and start the data restore process.  Once this has started it will call the New-VmFromIaasRestore runbook and close after reporting status to SNOW.

    This script is ONLY suitable to restore VMs that HAVE NOT been deleted as the VM configuration of the current VM is not stored with the backup object. VMs that have been deleted must be restored by hand.
    This will work with managed disk only.

    .NOTES
    Author:     Russell Pitcher/ Abhijit Pawar
    Company:    Atos
    Email:      russell.pitcher@atos.net/ abhijit.pawar@atos.net
    Created:    2017-03-27
    Updated:    2017-09-14
    Version:    1.2
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineResourceGroupName,

    # The name of the VM to back up
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineName,

    # The start of the range to look for restore points
    [Parameter(Mandatory=$false)]
    [String][ValidateNotNullOrEmpty()]
    $RecoveryPointWindowStart,

    # The end of the range to look for restore points
    [Parameter(Mandatory=$false)]
    [String][ValidateNotNullOrEmpty()]
    $RecoveryPointWindowEnd,

    # The recovery point ID for this job
    [Parameter(Mandatory=$false)]
    [String][ValidateNotNullOrEmpty()]
    $RecoveryPointId,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$false)]
    [String][ValidateNotNullOrEmpty()]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$false)]
    [String][ValidateNotNullOrEmpty()]
    $ConfigurationItemId
)

try {
    # Check that the right parameters have been supplied
    if ([string]::IsNullOrEmpty($RecoveryPointId)) {
        if ([string]::IsNullOrEmpty($RecoveryPointWindowStart) ){throw "You must supply either -RecoveryPointID or -RecoveryPointWindowStart and -RecoveryPointWindowEnd"}
        if ([string]::IsNullOrEmpty($RecoveryPointWindowEnd)) {throw "You must supply either -RecoveryPointID or -RecoveryPointWindowStart and -RecoveryPointWindowEnd"}
    }

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

    # Retrieve Recovery Vault from VM tag values
    Write-Verbose "Retrieving existing VM"
    $VM = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName

    if ($VM -eq $null) {
        throw "Cannot find VM '${VirtualMachineName}' in resource group '${VirtualMachineResourceGroupName}'.  If VM has already been deleted please perform a manual restore"
    }
    if ($VM.Tags.atosMaintenanceString2 -eq $null) {
        throw "Cannot find Recovery Vault to use - Cannot find atosMaintenanceString2 tag!"
    } else {
        $atosObject = $VM.Tags.atosMaintenanceString2 | ConvertFrom-JSON
        if ($atosObject.RSVault -eq $null) {
            throw "Cannot find Recovery Vault to use - RSVault value missing from atosMaintenanceString2 tag!"
        } else {
            $VaultName = $atosObject.RSVault
        }
    }

    # Save original configuration as text in case of problems
    $originalVmJSON = $VM | ConvertTo-JSON -Depth 99

    # Set Vault context
    Write-Verbose "Looking for backup vault: ${VaultName}"
    $BackupVault = Get-AzureRmRecoveryServicesVault -Name $VaultName
    if ($BackupVault -eq $null) {
        throw "Error retrieving backup vault ${VaultName}"
    }
    Write-Verbose "Setting Vault context"
    Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault

    ## Get recovery points in time frame
    Write-Verbose "Getting Named Container"
    $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType 'AzureVM' -Status 'Registered' -FriendlyName $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
    if ($namedContainer -eq $null) {
        throw "Error retrieving named container for ${VirtualMachineName} from vault ${VaultName}"
    }
    Write-Verbose "Getting Backup Item"
    $backupItem = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer -WorkloadType "AzureVM"
    if ($backupItem -eq $null) {
        throw "Error retrieving backup item for ${VirtualMachineName} from vault ${VaultName}"
    }
    $BackupPolicy = Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name $backupItem.ProtectionPolicyName

    if ([string]::IsNullOrEmpty($RecoveryPointId)) {
        # Convert parameters to DateTime
        try {
            $startDate = Get-Date $RecoveryPointWindowStart
        } catch {
            Write-Verbose "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
            throw "Invalid value for -RecoveryPointWindowStart. '${RecoveryPointWindowStart}' is not a valid date/time."
        }
        try {
            $endDate = Get-Date $RecoveryPointWindowEnd
        } catch {
            Write-Verbose "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
            throw "Invalid value for -RecoveryPointWindowEnd. '${RecoveryPointWindowEnd}' is not a valid date/time."
        }
        Write-Verbose "Finding restore points from $($startDate.ToString('u')) to $($endDate.ToString('u'))"
        $RecoveryPoints = Get-AzureRmRecoveryServicesBackupRecoveryPoint -Item $backupitem -StartDate $startdate.ToUniversalTime() -EndDate $enddate.ToUniversalTime()
        if ($RecoveryPoints.Count -eq 0) {
            throw "Failed to retrieve any recovery points for ${VirtualMachineName} from vault ${VaultName} in date range $($startDate.ToString('u')) to $($endDate.ToString('u'))"
        }

        Write-Verbose "Retrieved $($RecoveryPoints.Count) recovery point(s) within the specified date/time range:"
        forEach ($RecoveryPoint in $RecoveryPoints) {
            Write-Verbose " - Recovery point ID $($RecoveryPoint.RecoveryPointID) at time $($RecoveryPoint.RecoveryPointTime) with type $($RecoveryPoint.RecoveryPointType)"
        }
    } else {
        #Get the Recovery Point using Recovery point ID
        $RecoveryPointId = $RecoveryPointId.Trim()
        $RecoveryPoints = Get-AzureRmRecoveryServicesBackupRecoveryPoint -Item $backupitem | Where-Object -FilterScript {$_.RecoveryPointId -like $RecoveryPointId}
        if ($RecoveryPoints.Count -eq 0) {
            throw "Failed to retrieve any recovery points for ${VirtualMachineName} from vault ${VaultName} with recovery point ID '$RecoveryPointId'"
        }
    }

    ## Select the storage account to use
    if ($vm.StorageProfile.OsDisk.Vhd -eq $null) {
        Write-Verbose "OsDisk is MANAGED - Getting storage account from Resource Group"
        if ($VM.StorageProfile.OsDisk.ManagedDisk.StorageAccountType -match 'Premium') {
            $StorageAccountTier = 'Premium'
        } else {
            $StorageAccountTier = 'Standard'
        }
        $StorageAccounts = Get-AzureRmStorageAccount -ResourceGroupName $VirtualMachineResourceGroupName |
            Where-Object {$_.Sku.Tier -eq $StorageAccountTier}
        if ($StorageAccounts.Count -eq 0) {
            throw "Could not find any ${StorageAccountTier} storage accounts!"
        } else {
            Write-Verbose "Using a ${StorageAccountTier} storage account"
        }
        $StorageAccountName = $StorageAccounts[0].StorageAccountName
    } else {
        Write-Verbose "OsDisk is unmanaged - Getting storage account from VM object"
        $StorageAccountName = $VM.StorageProfile.OsDisk.Vhd.uri.split('.')[0].Replace('https://','')
    }
    Write-Verbose "Storage account that will be used is '${StorageAccountName}'"

    ## Start restore of latest recovery point within the time frame
    Write-Verbose "Starting restore of the most recent recovery point [$($RecoveryPoints[0].RecoveryPointID)]"
    $restoreJob = Restore-AzureRmRecoveryServicesBackupItem -RecoveryPoint $RecoveryPoints[0] -StorageAccountName $StorageAccountName -StorageAccountResourceGroupName $VirtualMachineResourceGroupName

    Write-Verbose "Started restore job with ID '$($restoreJob.JobId)' at $($restoreJob.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $restoreDetails = Get-AzureRmRecoveryServicesBackupJobDetails -job $restoreJob

    # Connect to the management subscription
    Write-Verbose "Connecting to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    $RunbookName = "New-VmFromIaasRestore"
    $RunbookParameters = @{
        SubscriptionId = $SubscriptionId
        VirtualMachineName = $VirtualMachineName
        VirtualMachineResourceGroupName = $VirtualMachineResourceGroupName
        RestoreJobId = $restoreDetails.JobId
        RequestorUserAccount = $RequestorUserAccount
        ConfigurationItemId = $ConfigurationItemId
    }

    Write-Verbose "Starting ${RunbookName} runbook with the following parameters:"
    $RunbookParameters.GetEnumerator() | ForEach-Object {
        Write-Verbose "  - $($_.Key)  =  $($_.Value)"
    }

    $RestoreRunbook = Start-AzureRmAutomationRunbook -Name $RunbookName -Parameters $RunbookParameters -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount
    Write-Verbose "VM Restoration has been initiated under JobId '$($RestoreRunbook.JobId)'"

    $status = "SUCCESS"
    $returnMessage = "Started restore of VM $($VM.Name) from recovery point at time $($RecoveryPoint.RecoveryPointTime) with type $($RecoveryPoint.RecoveryPointType).  VM restore will be completed under Azure job $($RestoreRunbook.JobId)"

} catch {
    $returnMessage = $_.ToString()
    Write-Verbose "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
    $status = "FAILURE"
}

Write-Output $status
Write-Output $returnMessage