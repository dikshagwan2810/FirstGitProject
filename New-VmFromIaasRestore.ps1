#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Restores an existing IaaS VM from a restored recovery point

    .DESCRIPTION
    This script will restore an already existing IaaS VM from an earlier backup that has been restored. It will also monitor a running recovery point restore and restore the VM once the data restore has completed.

    This script is ONLY suitable to restore VMs that HAVE NOT been deleted as the VM configuration of the current VM is not stored with the backup object. VMs that have already been deleted must be restored by hand following the data restoration.
    This operation supports only the VMs with managed disks. Blob based disks are not supported. 
    In case a VM that is a part of an availability set is restored, then  the VM will be added to the same availability set at the end of the operation.

    .NOTES
    Author:     Russell Pitcher, Austin Palakunnel
    Company:    Atos
    Email:      russell.pitcher@atos.net, austin.palakunnel@atos.net
    Created:    2017-03-27
    Updated:    2017-09-21
    Version:    1.4
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

    # The end of the range to look for restore points
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $RestoreJobId,

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
    # Record current Virtual machine's power status
    Write-Verbose "Recording VM's current power status"
    $VirtualMachineStatus = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status)
    $VirtualMachinePowerStatus = ($VirtualMachineStatus.Statuses | Where-Object {$_.code -like "PowerState/*"}).code
    $AvailabilitySetReference = $VM.AvailabilitySetReference
    if($AvailabilitySetReference -ne $null)
    {
        $AvailabilitySetName = $AvailabilitySetReference.Id.Split("/")[-1]
        $VM.AvailabilitySetReference = $null
    }
    
    $VMvnicName= $($VM.NetworkProfile.NetworkInterfaces.id).split("/")[-1]

    #remove network interface from lb
    $nic = Get-AzureRmNetworkInterface -Name $VMvnicName -ResourceGroupName $VirtualMachineResourceGroupName
    
    $VMLoadBalancerConfig = $nic.IpConfigurations[0].LoadBalancerBackendAddressPools
    if($VMLoadBalancerConfig.Id -ne $null)
    {
        $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $null
        $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
        if($setnic)
        {
            Write-Verbose "Removed vm $VirtualMachineName from  load balancer temporarily: $($VMLoadBalancerConfig.id)"
        }
        else
        {
            throw "Remove VM from LB temporarily: unable to Remove VM $VirtualMachineName from  load balancer : $($VMLoadBalancerConfig.id)"
        }
    }

    # Save original configuration as text in case of problems
    $originalVmJSON = $VM | ConvertTo-JSON -Depth 99

    # Set Vault context
    $BackupVault = Get-AzureRmRecoveryServicesVault -Name $VaultName
    if ($BackupVault -eq $null) {
        throw "Error retrieving backup vault ${VaultName}"
    }
    Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault

    $restoreJob = Get-AzureRmRecoveryServicesBackupJob -JobId $RestoreJobId
    ## Monitor restore job until is has completed
    do {
        Start-Sleep -Seconds 60
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $restorejob = Get-AzureRmRecoveryServicesBackupJob -JobId $RestoreJobId
        if ($null -eq $restorejob) {
            throw "Could not find a restore job with JobId ${RestoreJobId}"
        }
        Write-Verbose " - $now - Restore job $($restoreJob.status)"
    } until (($restoreJob.Status -match "Completed") -or ($restoreJob.Status -eq "Failed") -or ($restoreJob.Status -eq "Cancelled"))

    if ($restoreJob.Status -notMatch "Completed") {
        Write-Verbose "Data restore of ${VirtualMachineName} from vault ${VaultName}.  Restore jobID is ${RestoreJobId} and the status is $($restoreJob.Status))"
        throw "Data restore of ${VirtualMachineName} from vault ${VaultName}.  Restore jobID is ${RestoreJobId} and the status is $($restoreJob.Status))"
    }
    Write-Verbose "Data restore job completed"

    ## >>> Disks and config restored. Now to swap disks and re-create the VM <<< ##

    ## Get details of restore ##
    Write-Verbose "Retrieving restore details"
    $restoreDetails =  Get-AzureRmRecoveryServicesBackupJobDetails -job $restoreJob
    if ($restoreDetails -eq $null) {
        Write-Verbose "Failed to retrieve job details from restore job $($restoreJob.JobID)"
        throw "Failed to retrieve job details from restore job $($restoreJob.JobID)"
    }

    $restoreProperties = $restoreDetails.properties
    $storageAccountName = $restoreProperties["Target Storage Account Name"]
    $containerName = $restoreProperties["Config Blob Container Name"]
    $blobUri = $restoreProperties["Config Blob Uri"]
    $blobName = $restoreProperties["Config Blob Name"]

    Write-Verbose "Setting context and extracting restore configuration file"
    $storageAccountResult = Set-AzureRmCurrentStorageAccount -Name $StorageAccountName -ResourceGroupName $VirtualMachineResourceGroupName
    if ($storageAccountResult -eq $null) {
        Write-Verbose "Failed to set current storage account to ${StorageAccountName}"
        throw "Failed to set current storage account to ${StorageAccountName}"
    }

    $destinationPath = $(Get-Location).Path
    $blobContentResult = Get-AzureStorageBlobContent -Container $containerName -Blob $blobName -Destination $destinationPath
    $configJsonPath = Join-path -Path $destinationPath -ChildPath $blobContentResult.Name
    Write-Verbose "Configuration JSON path: ${configJsonPath}"
    $configJson = (Get-Content -Path $configJsonPath -Encoding Unicode).TrimEnd([char]0x00)

    # Convert changed property names
    $properties = "hardwareProfile","storageProfile","osProfile","networkProfile","diagnosticsProfile","availabilitySet","provisioningState","instanceView","licenseType","vmId"
    forEach ($property in $properties) {
        $configJson = $configJson.Replace("`"properties.${property}`"","`"${property}`"")
    }

    $restoreConfig = $configJson | ConvertFrom-Json


    # Record current monitoring setting
    $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VM -TagName atosMaintenanceString2 -KeyName MonStatus

    # Enable maintenance mode and update SNow if necessary
    switch ($MonitoringSetting) {
        "Monitored"{
            # Enable Maintenance Mode and update SNow
            Write-Verbose "Entering Maintenance Mode during VM restore"
            $MonitoringResult = Disable-OMSAgent -SubscriptionId $SubscriptionId -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -Runbook $Runbook -EnableMaintenanceMode:$true
            if ($MonitoringResult[0] -eq "SUCCESS") {
                Write-Verbose "Successfully entered maintenance mode"
            } else {
                throw "Failed to enter maintenance mode: $($MonitoringResult[1])"
            }
            break
        }
        "NotMonitored" {
            Write-Verbose "VM is not monitored, skipping maintenance mode"
            break
        }
        "MaintenanceMode" {
            Write-Verbose "VM is already in maintenance mode"
            break
        }
        default {
            Write-Verbose "MonStatus is not set setting to NotMonitored"
            $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $VM
            break
        }
    }
    $VM = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName


    # Get details from existing machine
    Write-Verbose "Stopping existing VM"
    $StopResult = Stop-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force
    if ($StopResult.Status -ne "Succeeded") {
        Write-Verbose "Failed to stop original VM ${VirtualMachineName} successfully. Stop status is '$($StopResult.Status)' and error is '$($StopResult.Error)'"
        throw "Failed to stop original VM ${VirtualMachineName} successfully. Stop status is '$($StopResult.Status)' and error is '$($StopResult.Error)'"
    }

    Write-Verbose "Getting replacement VM details from existing VM"
    $OldVmInfo = New-Object PSObject -Property @{
        OsType = $VM.StorageProfile.OsDisk.OsType
        ResourceGroup = $VM.ResourceGroupName
        Location = $VM.Location
        OsDiskID = $VM.StorageProfile.OsDisk.ManagedDisk.Id
        OsDiskName = $VM.StorageProfile.OsDisk.Name
    }

    Write-Verbose "Getting names for any data disks"
    $OldVmDataDisks = @{}
    forEach ($DataDisk in $VM.StorageProfile.DataDisks) {
        $OldVmDataDisks.Add($DataDisk.Lun, $DataDisk.Name)
    }

    # Retrieve list of disks from VM
    $VHDList = @()
    $VHDList += $VM.StorageProfile.OsDisk.ManagedDisk.Id
    forEach ($Vhd in ($VM.StorageProfile.DataDisks.ManagedDisk.Id)) {
        $VHDList += $Vhd
    }

    Write-Verbose "Original VM info:"
    Write-Verbose $OldVmInfo

    # Remove illegal settings
    Write-Verbose "Removing disallowed values"
    $VM.OSProfile = $null
    $VM.StorageProfile.ImageReference = $null

    Write-Verbose "Removing old OS disk : $($VM.StorageProfile.OsDisk.Name)"
    $VM.StorageProfile.OsDisk = $null

    Write-Verbose "Removing original data disks from VM reference object"
    forEach ($dataDisk in $VM.StorageProfile.DataDisks) {
        Write-Verbose " - Removing old data disk: $($dataDisk.Name)"
        $RemoveResult = Remove-AzureRmVMDataDisk -VM $VM -Name $dataDisk.Name
    }

    Write-Verbose "Attaching new OS disk: $($restoreConfig.StorageProfile.OSDisk.Name)"
    switch ($OldVmInfo.OsType) {
        "Windows" {
            $VM = Set-AzureRmVMOSDisk -VM $Vm -VhdUri $restoreConfig.StorageProfile.OSDisk.vhd.Uri -name $OldVmInfo.OSDiskName.Replace("$($VM.Name)_",'') -CreateOption attach -Windows -Caching $VM.StorageProfile.OsDisk.Caching
        }
        "Linux" {
            $VM = Set-AzureRmVMOSDisk -VM $Vm -VhdUri $restoreConfig.StorageProfile.OSDisk.vhd.Uri -name $OldVmInfo.OSDiskName.Replace("$($VM.Name)_",'') -CreateOption attach -Linux -Caching $VM.StorageProfile.OsDisk.Caching
        }
    }

    Write-Verbose "Setting OsType to $($OldVmInfo.OsType)"
    $VM.StorageProfile.OsDisk.OsType = $OldVmInfo.OsType

    if ($VM.StorageProfile.OsDisk.CreateOption -ne "attach") {
        Write-Verbose "OsDisk.CreateOption = $($VM.StorageProfile.OsDisk.CreateOption).  Changing to 'attach'"
        $VM.StorageProfile.OsDisk.CreateOption = 'attach'
    }

    Write-Verbose "Adding restored data disks (if any)"
    ForEach ($DataDisk in $restoreConfig.StorageProfile.DataDisks) {
        Write-Verbose " - Adding restored data disk: $($OldVmDataDisks[$DataDisk.Lun]) [$($DataDisk.Name)]"
        $VM = Add-AzureRmVMDataDisk -VM $VM  `
            -Lun $DataDisk.Lun `
            -Caching $DataDisk.Caching `
            -CreateOption 'attach' `
            -DiskSizeInGB $DataDisk.DiskSizeGB `
            -Name $OldVmDataDisks[$DataDisk.Lun].Replace("$($VM.Name)_",'') `
            -VhdUri $DataDisk.vhd.Uri
    }

    Write-Verbose "The restore config now has the following data disks:"
    forEach ($DataDisk in $VM.StorageProfile.DataDisks) {
        Write-Verbose "- $($DataDisk.Name), Lun $($DataDisk.Lun), Caching $($DataDisk.Caching), CreateOption $($DataDisk.CreateOption)"
    }

    Write-Verbose "Setting HardwareProfile"
    $VM.HardwareProfile.VmSize = $restoreConfig.HardwareProfile.vmSize

    # Save restore configuration as text in case of problems
    $restoreVmJSON = $VM | ConvertTo-JSON -Depth 99

    # Remove the original VM
    Write-Verbose "Deleting original VM"
    $RemoveVMResult = $VM | Remove-AzureRmVm -Force
    if ($RemoveVMResult.Status -ne "Succeeded") {
        Write-Verbose "Failed to remove original VM.  Remove status = '$($RemoveVMResult.Status)', Error = '$($RemoveVMResult.Error)'"
        throw "Failed to remove original VM.  Remove status = '$($RemoveVMResult.Status)', Error = '$($RemoveVMResult.Error)'"
    }

    # Remove original managed disks
    Write-Verbose "Removing original managed disks"
    forEach ($VHD in $VHDList) {
        $VHDName = $VHD.Split("/")[-1]
        Write-Verbose " - Removing Disk ${VHDName} from ResourceGroup ${VirtualMachineResourceGroupName}"
        $result = Remove-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $VHDName -Force
        if ($result.status -ne 'Succeeded') {
            Write-Verbose "  Failed to delete disk: ${VHDName}"
        }
    }

    Write-Verbose "Waiting 1 minute, just in case"
    Start-Sleep -Seconds 60


    # Re-deploy the restored VM
    Write-Verbose "Redeploying VM with restored disks"
    $VM.AvailabilitySetReference = $null
    $restoredVm = New-AzureRmVm -ResourceGroupName $OldVmInfo.ResourceGroup -Location $OldVmInfo.Location -VM $VM -WarningAction Ignore -ErrorAction Stop

    if ($restoredVm.IsSuccessStatusCode -eq $true) {
        $returnMessage = "Successfully restored VM $($VM.Name)"

        Write-Verbose "Successfully restored VM $($VM.Name)"
        Write-Verbose "Stopping VM $($VM.Name) before disk conversion"
        $StopResult = Stop-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VM.Name -Force
        if ($StopResult.Status -ne "Succeeded") {
            throw "Unable to stop VM.  Status = '$($ConvertResult.Status)', Error = '$($StopResult.Error)'"
        }

        Write-Verbose "Converting VM to use managed disks"
        $ConvertResult = ConvertTo-AzureRmVMManagedDisk -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VM.Name
        if ($ConvertResult.Status -ne "Succeeded") {
            throw "Unable to stop VM.  Status = '$($ConvertResult.Status)', Error = '$($ConvertResult.Error)'"
        } else {
            Write-Verbose "Converted VM to managed successfully"
        }        

        ###If VM was part of Availability set, remove Vm again and redeploy to add to Availability set
        if($AvailabilitySetReference -ne $null)
        {
            
            #Create VM profile of the restored VM with Availability set
            Write-Verbose "Deleting restored VM to add to Availability Set $AvailabilitySetName"

            $restoredVm1 = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
            $VMinASConfig = $restoredVm1
            $VMinASConfig.AvailabilitySetReference = $AvailabilitySetReference
            if($restoredVm1.StorageProfile.OsDisk.OsType -like "Windows")
            {
                $VMinASConfig = Set-AzureRmVMOSDisk -VM $VMinASConfig -ManagedDiskId $restoredVm1.StorageProfile.OsDisk.ManagedDisk.Id  -Name $restoredVm1.Name -CreateOption Attach -Windows
            }
            else
            {
                $VMinASConfig = Set-AzureRmVMOSDisk -VM $VMinASConfig -ManagedDiskId $restoredVm1.StorageProfile.OsDisk.ManagedDisk.Id  -Name $restoredVm1.Name -CreateOption Attach -Linux
            }
            
            #Add Data Disks
            foreach ($disk in $restoredVm1.StorageProfile.DataDisks ) { 
                $VMinASConfig = Add-AzureRmVMDataDisk -VM $VMinASConfig -Name $disk.Name -ManagedDiskId $disk.ManagedDisk.Id -Caching $disk.Caching -Lun $disk.Lun -CreateOption Attach -DiskSizeInGB $disk.DiskSizeGB
            }
            
            

            #Remove Vm and Redeploy
            $RemoveVMResult1 = $restoredVm1 | Remove-AzureRmVm -Force
            if ($RemoveVMResult1.Status -ne "Succeeded") {
                Write-Verbose "Failed to remove restored VM.  Remove status = '$($RemoveVMResult1.Status)', Error = '$($RemoveVMResult1.Error)'"
                throw "Failed to remove restored VM.  Remove status = '$($RemoveVMResult1.Status)', Error = '$($RemoveVMResult1.Error)'"
            }
            Write-Verbose "Waiting 1 minute, just in case"
            Start-Sleep -Seconds 60

            Write-Verbose "Redeploying VM to add to availability set $AvailabilitySetName"
            $restoredVm = New-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Location $restoredVm1.Location -VM $VMinASConfig -WarningAction Ignore -ErrorAction Stop
            if ($restoredVm.IsSuccessStatusCode -eq $true) {
                $returnMessage = "Successfully restored VM $($VM.Name)"

                Write-Verbose "Successfully restored VM $($VM.Name) and added to availability set $AvailabilitySetName"

                if($VMLoadBalancerConfig.Id -ne $null)
                {
                    $VMvnicName1 = $($VM.NetworkProfile.NetworkInterfaces.id).split("/")[-1]

                    #Add network interface to lb
                    $nic1 = Get-AzureRmNetworkInterface -Name $VMvnicName1 -ResourceGroupName $VirtualMachineResourceGroupName
                    
                    $nic1.IpConfigurations[0].LoadBalancerBackendAddressPools = $VMLoadBalancerConfig
                    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic1
                    if($setnic)
                    {
                        Write-Verbose "Added vm $VirtualMachineName back to load balancer : $($VMLoadBalancerConfig.id)"
                    }
                    else
                    {
                        throw "Add VM back to LB : unable to add VM $VirtualMachineName to  load balancer : $($VMLoadBalancerConfig.id)"
                    }
                    
                }

                #$status = "SUCCESS"
            }
            else
            {                
                $status = "FAILURE"
                $returnMessage = "Failed to add VM $($VM.Name) to Availability Set $AvailabilitySetName. StatusCode is '$($restoredVm.IsSuccessStatusCode)'' and ReasonPhrase is '$($restoredVm.ReasonPhrase)'"
            }
            #End Remove and Redeploy
        }
        $restoredVm = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName


        # Disable Maintenance Mode and update SNow if necessary
        switch ($MonitoringSetting) {
            "Monitored"{
                Write-Verbose "Exiting maintenance mode and re-enabling monitoring"
                $MonitoringResult = Enable-OMSAgent -SubscriptionId $SubscriptionId -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -Runbook $Runbook
                if ($MonitoringResult[0] -eq "SUCCESS") {
                    Write-Verbose "Successfully exited maintenance mode"
                } else {
                    throw "Failed to exit maintenance mode: $($MonitoringResult[1])"
                }
                break
            }
            "NotMonitored" {
                Write-Verbose "VM is not monitoried"
                break
            }
            "MaintenanceMode" {
                Write-Verbose "Leaving VM in maintenance mode"
                break
            }
            default {
                Write-Verbose "MonStatus is not set setting to NotMonitored"
                $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $restoredVm 
                break
            }
        }

        # Removing restored unmanaged disk and restore config blobs
        Write-Verbose "Gathering list of BLOBs to be removed"
        $blobUriList = @()
        $blobUriList += $blobUri   # Restore config JSON blob
        $blobUriList += $restoreConfig.storageProfile.osDisk.vhd.uri
        forEach ($Vhd in ($restoreConfig.StorageProfile.DataDisks.vhd.Uri)) {
            $blobUriList += $Vhd
        }

        Write-Verbose "Removing unneeded BLOBs"
        forEach ($BlobUri in $blobUriList) {
            $StorageAcc = $BlobUri.Split("/").Split(".")[2]
            $BlobName = $BlobUri.Split("/")[-1]
            $ContainerName = $BlobUri.Split("/")[-2]
            Write-Verbose " - Removing Blob ${BlobName} from account ${StorageAcc} container ${ContainerName}"
            $RemoveBlob = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like $StorageAcc} |
                Get-AzureStorageContainer | Where-Object {$_.name -like $ContainerName} |
                Remove-AzureStorageBlob -Blob $BlobName
            if (!$?) {
                # Remove-AzureStorageBlob does not return anything, so we just check that the command succeeded and hope for the best
                Write-Verbose "Failed to remove blob ${BlobName}"
            }
        }

        # Removing Restore container
        Write-Verbose "Removing Restore BLOBs container"
        $RemoveContainer = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like $StorageAcc} |
            Get-AzureStorageContainer | Where-Object {$_.name -like $ContainerName} |
            Remove-AzureStorageContainer -Force
        if (!$?) {
            # Remove-AzureStorageContainer does not return anything, so we just check that the command succeeded and hope for the best
            Write-Verbose "Failed to remove container ${ContainerName}"
        }

        # Power off VM if it was powered-off before the restore
        if ($VirtualMachinePowerStatus -ne 'PowerState/running') {
            Write-Verbose "Shutting down ${VirtualMachineName}"
            $StopVM = Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force
            if ($StopVM.Status -eq 'Succeeded') {
                Write-Verbose "Successfully deallocated VM: ${VirtualMachineName}"
            } else {
                Write-Verbose "Shut down of VM ${VirtualMachineName} failed with status $($StopVM.Status)"
                $status = "WARNING"
            }
        }
        if ($status -notlike "FAILURE") {
            try {
                Write-Verbose "Re-enabling backup"
                $BackupResult = Enable-AtosIaasVmBackup -SubscriptionId $SubscriptionId -VirtualMachineName $VirtualMachineName -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName
                if ($BackupResult[0] -eq "SUCCESS") {
                    $status = "SUCCESS"
                    $returnMessage += " and re-enabled backup"
                } else {
                    $status = "FAILURE"
                    $returnMessage += " but FAILED to re-enable backup"
                }
            } catch {
                $status = "FAILURE"
                $returnMessage += " but FAILED to re-enable backup"
                $returnMessage += $_.ToString()
            }
        } else {
            $status = "FAILURE"
            $returnMessage += $_.ToString()
            $returnMessage += " and FAILED to re-enable backup"
        }
    } else {
        $status = "FAILURE"
        $returnMessage = "Failed to restore VM $($VM.Name). StatusCode is '$($restoredVm.IsSuccessStatusCode)'' and ReasonPhrase is '$($restoredVm.ReasonPhrase)'"
    }
} catch {
    $returnMessage = "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
    $status = "FAILURE"
    Write-Verbose ">>>> ERROR details <<<<"
    Write-Verbose ">> Error Message : $($_.ToString())"
    Write-Verbose ">> ScriptName    : $($_.InvocationInfo.ScriptName.Split('\')[-1])"
    Write-Verbose ">> Line text     : $($_.InvocationInfo.Line.Trim())"
    Write-Verbose ">> Stack Trace   :"
    Write-Verbose ">>   $($_.ScriptStackTrace.Replace(""`n"", ""`nVERBOSE: >>   ""))"
}

Write-Output $status
Write-Output $returnMessage