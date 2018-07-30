#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Script to create, delete and restore snapshot.

    .DESCRIPTION
    Script to create, delete and restore snapshot.
    The script will create the snapshot of the VM and also create the table in Azure.
    The script will delete the snapshot of the VM and also will clear the table in Azure.
    The script will restore the snapshot of the VM to the state of the snapshot.

    .NOTES
    Author:     Ankita Chaudhari
    Company:    Atos
    Email:      ankita.chaudhari@atos.net
    Created:    2017-01-12
    Updated:    2017-05-15
    Version:    1.3

    .Note
    1.0 - Enable the Log verbose records of runbook
    1.1 - Updated to use module and harmonize parameters
    1.2 - Check for premium storage and stop if found
    1.3 - Force use of first standard storage account in VM's resource group to allow snaps on premium storage
#>

param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    # The GUID of the snapshot to act upon
    [Parameter(Mandatory=$false)]
    [String]
    $SnapshotId,

    # The name of/for the snapshot
    [Parameter(Mandatory=$false)]
    [String]
    $SnapshotName,

    # The description of the snapshot
    [Parameter(Mandatory=$false)]
    [String]
    $SnapshotDescription,

    # The action to perform on the snapshot.  Must be one of Create, Delete or Retrieve
    [Parameter(Mandatory=$True)]
    [String]
    $SnapshotAction,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

function Get-StorageTable {
    Param(
        [Parameter(Mandatory=$true)]
        $TableName,

        [Parameter(Mandatory=$true)]
        $StorageContext
    )
    $StorageTable = Get-AzureStorageTable -Context $StorageContext | Where-Object {$_.CloudTable.Name -eq $TableName}
    if (!($StorageTable)) {
        $StorageTable = New-AzureStorageTable -Name $TableName -Context $StorageContext
    }
    return $StorageTable
}

function Retrieve-SnapInfo {
    Param(
        $VirtualMachineName,

        $SnapGUID,

        [Parameter(Mandatory=$true)]
        $StorageContext
    )

    $TableName = "AzureSnapTable"

    $SnapTable = Get-StorageTable -TableName $TableName -StorageContext $StorageContext

    $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
    if ($SnapGUID) {
        $query.FilterString = "PartitionKey eq '${SnapGUID}'"
    }

    $SnapInfo = $SnapTable.CloudTable.ExecuteQuery($query)
    forEach ($snap in $SnapInfo) {
        $OutputItem = "" | Select-Object VMName, SnapshotName, DiskNum, SnapGUID, `
                                        PrimaryUri, SnapshotUri, SnapshotDescription, `
                                        SnapshotTime, Lun, DiskSizeGB, Caching, `
                                        HardwareProfile, DiskType
        $OutputItem.SnapGUID = $Snap.PartitionKey
        $OutPutItem.DiskNum = $Snap.RowKey
        $OutputItem.VMName = $Snap.Properties.VMName.StringValue
        $OutputItem.PrimaryUri = $Snap.Properties.BaseURI.StringValue
        $OutputItem.SnapshotUri = $Snap.Properties.SnapshotURI.StringValue
        $OutputItem.SnapshotName = $Snap.Properties.SnapshotName.StringValue
        $OutputItem.SnapshotDescription = $Snap.Properties.SnapshotDescription.StringValue
        $OutputItem.SnapshotTime = $Snap.Properties.SnapshotTime.StringValue
        $OutputItem.Lun = $Snap.Properties.Lun.Int32Value
        $OutputItem.DiskSizeGB = $Snap.Properties.DiskSizeGB.Int32Value
        $OutputItem.Caching = $Snap.Properties.Caching.StringValue
        $OutputItem.HardwareProfile = $Snap.Properties.HardwareProfile.StringValue
        $OutputItem.DiskType = $Snap.Properties.DiskType.StringValue
        if ($VirtualMachineName) {
            $OutputItem | Where-Object {$_.VMName -eq $VirtualMachineName}
        } else {
            $OutputItem
        }
    }
}

function Write-SnapInfo {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachineName,

        [Parameter(Mandatory=$true)]
        $DiskNum,

        [Parameter(Mandatory=$true)]
        $SnapGUID,

        [Parameter(Mandatory=$true)]
        $PrimaryUri,

        [Parameter(Mandatory=$true)]
        $SnapshotUri,

        [Parameter(Mandatory=$true)]
        $SnapshotName,

        [Parameter(Mandatory=$false)]
        $SnapshotDescription = "",

        [Parameter(Mandatory=$true)]
        $StorageContext,

        [Parameter(Mandatory=$true)]
        [int]
        $Lun,

        [Parameter(Mandatory=$true)]
        [int]
        $DiskSizeGB,

        [Parameter(Mandatory=$true)]
        [string]
        $Caching,

        [Parameter(Mandatory=$true)]
        [string]
        $HardwareProfile,

        [Parameter(Mandatory=$true)]
        $DiskType
    )

    $TableName = "AzureSnapTable"

    Write-Verbose "Storage Context : ${StorageContext}"
    $SnapTable = Get-StorageTable -TableName $TableName -StorageContext $StorageContext

    $entity = New-Object "Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity" $SnapGUID, $DiskNum
    $entity.Properties.Add("VMName", $VirtualMachineName)
    $entity.Properties.Add("BaseURI", $PrimaryUri)
    $entity.Properties.Add("SnapshotURI", $SnapshotUri)
    $entity.Properties.Add("SnapshotName", $SnapshotName)
    $entity.Properties.Add("SnapshotDescription", $SnapshotDescription)
    $entity.Properties.Add("Lun", $Lun)
    $entity.Properties.Add("DiskSizeGB", $DiskSizeGB)
    $entity.Properties.Add("Caching", $Caching)
    $entity.Properties.Add("HardwareProfile", $HardwareProfile)
    $entity.Properties.Add("SnapshotTime", ((Get-Date).ToString()))
    $entity.Properties.Add("DiskType", $DiskType)

    $result = $SnapTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity))
}

function Clear-SnapInfo {
    Param (
        [Parameter(Mandatory=$true)]
        $SnapGUID,

        [Parameter(Mandatory=$true)]
        $StorageContext
    )
    $TableName = "AzureSnapTable"

    $SnapTable = Get-StorageTable -TableName $TableName -StorageContext $StorageContext

    $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
    $query.FilterString = "PartitionKey eq '${SnapGUID}'"

    $SnapInfo = $SnapTable.CloudTable.ExecuteQuery($query)
    forEach ($Snap in $SnapInfo) {
        $result = $SnapTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Delete($Snap))
    }
}

function Get-DiskInfo {
    Param (
        $DiskUri,
        $VirtualMachine
    )
    $DiskInfoTable = "" | Select-Object Uri, StorageAccountName, VHDName, `
                                        ContainerName, DiskType, Caching, `
                                        Lun, DiskSizeGB
    $OSDiskDetails = $VirtualMachine.storageprofile.OsDisk
    $DataDisk = $VirtualMachine.storageprofile.DataDisks | Where-Object {$_.vhd.Uri -eq $DiskUri}

    if ($VirtualMachine.storageprofile.osdisk.vhd.Uri -eq $DiskUri) {
        $DiskInfoTable.Uri = $OSDiskDetails.Vhd.Uri
        $DiskInfoTable.StorageAccountName = ($($OSDiskDetails.Vhd.Uri) -split "https://")[1].Split(".")[0]
        $DiskInfoTable.VHDName = $($OSDiskDetails.Vhd.Uri).Split("/")[-1]
        $DiskInfoTable.ContainerName = $($OSDiskDetails.Vhd.Uri).Split("/")[3]
        $DiskInfoTable.DiskType = "OSDisk"
        $DiskInfoTable.Caching = $OSDiskDetails.Caching
        $DiskInfoTable.Lun = ""
        $DiskInfoTable.DiskSizeGB = ""
    } else {
        $DiskInfoTable.Uri = $DataDisk.Vhd.Uri
        $DiskInfoTable.StorageAccountName = ($($DataDisk.Vhd.Uri) -split "https://")[1].Split(".")[0]
        $DiskInfoTable.VHDName = $($DataDisk.Vhd.Uri).Split("/")[-1]
        $DiskInfoTable.ContainerName = $( $DataDisk.Vhd.Uri).Split("/")[3]
        $DiskInfoTable.DiskType = "DataDisk"
        $DiskInfoTable.Caching = $DataDisk.Caching
        $DiskInfoTable.Lun = $DataDisk.lun
        $DiskInfoTable.DiskSizeGB = $DataDisk.DiskSizeGB
    }

    return $DiskInfoTable
}

function Get-DiskInfoFromUri {
    Param (
        [Parameter(Mandatory=$true)]
        $DiskUri
    )

    $DiskUriInfo = New-Object PsObject -Property @{
        Uri = $DiskUri
        StorageAccountName = $DiskUri.Split('/')[2].Split('.')[0]
        VHDName = $DiskUri.Split('/')[-1]
        ContainerName = $DiskUri.Split('/')[3]
    }

    return $DiskUriInfo
}

function Get-StorageContextForUri {
    Param (
        [Parameter(Mandatory=$true)]
        $DiskUri
    )

    $StorageAccountName = $DiskUri.Split('/')[2].Split('.')[0]
    $StorageAccountResource = Find-AzureRmResource -ResourceNameContains $StorageAccountName -WarningAction Ignore
    $StorageKey = Get-AzureRmStorageAccountKey -Name $StorageAccountResource.Name -ResourceGroupName $StorageAccountResource.ResourceGroupName
    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountResource.Name -StorageAccountKey $StorageKey[0].Value

    return $StorageContext
}

function Get-StandardStorageContextForResourceGroup {
    Param (
        [Parameter(Mandatory=$true)]
        $ResourceGroupName
    )

    $StandardStorageAccounts = (Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName | Where-Object {$_.sku.tier -eq 'Standard'})
    $StorageKey = Get-AzureRmStorageAccountKey -Name $StandardStorageAccounts[0].StorageAccountName -ResourceGroupName $StandardStorageAccounts[0].ResourceGroupName
    $StorageContext = New-AzureStorageContext -StorageAccountName $StandardStorageAccounts[0].StorageAccountName -StorageAccountKey $StorageKey[0].Value

    return $StorageContext
}

function Get-AzureRMVMSnapBlobs {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachine
    )

    $DiskUriList=@()
    $DiskUriList += $VirtualMachine.StorageProfile.OsDisk.Vhd.Uri

    forEach ($Disk in $VirtualMachine.StorageProfile.DataDisks) {
        $DiskUriList += $Disk.Vhd.Uri
    }

    forEach ($DiskUri in $DiskUriList) {
        $DiskInfo = Get-DiskInfoFromUri -DiskUri $DiskUri
        $StorageContext = Get-StorageContextForUri -DiskUri $DiskUri
        Get-AzureStorageBlob -Container $DiskInfo.ContainerName -Context $StorageContext | Where-Object {
            $_.Name -eq $DiskInfo.VHDName `
            -and $_.ICloudBlob.IsSnapshot `
            -and $_.SnapshotTime -ne $null
        }
    }
}

function Disk-Validation {
    Param (
        $DiskUri,
        $SnapInfo
    )

    $matched=""
    $StorageAcc = ($DiskUri.Split("/")[2]).split(".")[0]
    $Container = $DiskUri.Split("/")[3]
    $BlobName = $DiskUri.Split("/")[4]
    $blob = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "$StorageAcc"} |
            Get-AzureStorageContainer | Where-Object {$_.Name -like "$Container"} |
            Get-AzureStorageBlob
    $isSnapshot = $blob.ICloudBlob | Where-Object {$_.SnapshotQualifiedUri -like "*($BlobName)?*"}
    if ($isSnapshot.Count -gt 0) {
        if ($isSnapshot.IsSnapshot -like $true) {
            forEach ($Snapshot in $SnapInfo) {
                if ($Snapshot.primaryUri -eq $DiskUri) {
                    $matched = $true
                }
            }
        }
    } else {
        $matched = $false
    }

    return $matched
}

function New-AzureRMVMSnap {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachineName,

        [Parameter(Mandatory=$true)]
        $VirtualMachineResourceGroupName,

        [Parameter(Mandatory=$true)]
        $SnapshotName,

        $SnapshotDescription
    )

    Write-Verbose "Create Snapshot for VM:"
    Write-Verbose $VirtualMachineName

    $VM = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName

    #Getting the VM PowerState
    $TempVMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status)
    $VMStatus = ($TempVMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code

    #Checking the VM PowerState
    if($VMStatus -eq "PowerState/running")
    {
        throw "Virtual Machine $VirtualMachineName is in Running state. Please Stop(Deallocate) the machine to Create the snapshot."
    }

    if ($VM) {
        $SnapshotId = New-GUID

        Write-Verbose "Gathering disk URIs"
        $DiskUriList=@()
        $DiskUriList += $VM.StorageProfile.OsDisk.Vhd.Uri
        forEach ($Disk in $VM.StorageProfile.DataDisks) {
            $DiskUriList += $Disk.Vhd.Uri
        }

        Write-Verbose "Retrieving Snapshot table storage context"

        # Get context from first standard storage account in resource group rather than OsDisk so we can snap VMs with Premium storage too
        $SnapTableStorageContext = Get-StandardStorageContextForResourceGroup -ResourceGroupName $VirtualMachineResourceGroupName

        # $DiskUri = $DiskUriList[0]
        $SnapshotTableInfo=@()
        forEach ($DiskUri in $DiskUriList) {
            Write-Verbose "Snapshot disk: ${DiskUri}"

            $DiskInfo = Get-DiskInfo -VirtualMachine $VM -DiskUri $DiskUri
            $StorageContext = Get-StorageContextForUri -DiskUri $DiskUri
            $DiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName -Context $StorageContext -Blob $DiskInfo.VHDName

            ## Create Snapshot
            $Snapshot = $DiskBlob.ICloudBlob.CreateSnapshot()

            Write-Verbose "  -Lun $($DiskInfo.Lun)"
            Write-Verbose "  -DiskSizeGB $($DiskInfo.DiskSizeGB)"
            Write-Verbose "  -Caching $($DiskInfo.Caching)"
            Write-Verbose "  -HardwareProfile $($VM.HardwareProfile.VmSize)"

            Write-SnapInfo -VirtualMachineName $VirtualMachineName `
                        -SnapGUID $SnapshotId `
                        -PrimaryUri $DiskInfo.Uri.ToString() `
                        -SnapshotUri $Snapshot.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString() `
                        -StorageContext $SnapTableStorageContext `
                        -DiskNum $DiskUriList.IndexOf($DiskUri) `
                        -SnapshotName $SnapshotName `
                        -SnapshotDescription $SnapshotDescription `
                        -Lun $DiskInfo.Lun `
                        -DiskSizeGB $DiskInfo.DiskSizeGB `
                        -Caching $DiskInfo.Caching `
                        -HardwareProfile $VM.HardwareProfile.VmSize `
                        -DiskType $DiskInfo.DiskType
        }

        if ($VMState.Status `
            -eq "VM Running") {
            Write-Verbose "Restarting VM..."
            $Started = $VM | Start-AzureRMVM
        }

        $SnapInfo = Retrieve-SnapInfo -VirtualMachineName $VirtualMachineName -SnapGUID $SnapshotId -StorageContext $SnapTableStorageContext
        $SnapshotTime = $SnapInfo.SnapshotTime
    } else {
        Write-Verbose "Unable to get VM"
    }

    $Result = @{
        "SnapshotId" = "$SnapshotId"
        "SnapshotTime" = "$SnapshotTime"
    }
    return $Result
}

function Get-AzureRMVMSnap {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachineName,

        $SnapshotId,

        [switch]
        $GetBlobs = $False
    )

    $VM = Get-AzureRmVM | Where-Object {$_.Name -eq $VirtualMachineName}
    if ($VM) {
        $OSDiskUri = @()
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri

        # Get context from first standard storage account in resource group rather than OsDisk so we can snap VMs with Premium storage too
        $SnapTableStorageContext = Get-StandardStorageContextForResourceGroup -ResourceGroupName $VM.ResourceGroupName

        if ($SnapshotId) {
            $SnapInfo = Retrieve-SnapInfo -VirtualMachineName $VirtualMachineName -StorageContext $SnapTableStorageContext -SnapGUID $SnapshotId
        } else {
            $SnapInfo = Retrieve-SnapInfo -VirtualMachineName $VirtualMachineName -StorageContext $SnapTableStorageContext
        }


        if ($GetBlobs) {
            $SnapshotBlobs = Get-AzureRMVMSnapBlobs -VirtualMachine $VM
            forEach ($SnapInfo in $SnapInfo) {
                $SnapshotBlobs | Where-Object {
                    $_.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString() -eq $SnapInfo.SnapshotUri.ToString()
                }
            }
        } else {
            $SnapInfo
        }
    }
}

function Delete-AzureRMVMSnap {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachineName,

        [Parameter(Mandatory=$true)]
        $VirtualMachineResourceGroupName,

        $SnapshotId
    )

    $VM = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
    if ($VM) {
        $OSDiskUri = $VM.StorageProfile.OsDisk.Vhd.Uri

        # Get context from first standard storage account in resource group rather than OsDisk so we can snap VMs with Premium storage too
        $SnapTableStorageContext = Get-StandardStorageContextForResourceGroup -ResourceGroupName $VirtualMachineResourceGroupName

        $SnapInfo = Retrieve-SnapInfo -VirtualMachineName $VirtualMachineName -StorageContext $SnapTableStorageContext
        $UniqueGuids = $SnapInfo | ForEach-Object {$_.SnapGuid} | Sort-Object -Unique
        if ($SnapshotId) {
                $UniqueGuids = $UniqueGuids | Where-Object {$_ -eq $SnapshotId}
        }
        if ($UniqueGuids -ne $null) {
            forEach ($Guid in $UniqueGuids) {
                $snapdisk = $SnapInfo | Where-Object {$_.SnapGUID -eq $Guid}

                Write-Verbose "Deleting the snap"
                $SnapBlobs = Get-AzureRMVMSnap -VirtualMachineName $VirtualMachineName -SnapshotId $Guid -GetBlobs
                $SnapBlobs | ForEach-Object {$_.ICloudBlob.Delete()}

                Write-Verbose "Clearing the snap info"
                Clear-SnapInfo -SnapGUID $Guid -StorageContext $SnapTableStorageContext
                $DataDisks = $snapdisk | Where-Object {$_.DiskType -like "DataDisk"}
                $DiskToBeDeleted=@()
                # Verify if the VM have additional disk which is not there in snap
                if (($DataDisks.DiskNum).count -gt 0) {
                    forEach ($DataDisk in $DataDisks) {
                        $DiskMatched = $False
                        forEach ($VMDataDisk in $VM.StorageProfile.DataDisks) {
                            if ($DataDisk.PrimaryUri -eq $VMDataDisk.Vhd.Uri) {
                                $DiskMatched = $true
                            }
                        }
                        if ($DiskMatched -ne $true) {
                            $DiskToBeDeleted += $DataDisk.PrimaryUri
                        }
                    }
                }
            }
        } else {
            Write-Verbose "Snapshot not found"
        }
    } else {
        Write-Verbose "Unable to find VM"
    }

    return $DiskToBeDeleted
}

function Revert-AzureRMVMSnap {
    Param (
        [Parameter(Mandatory=$true)]
        $VirtualMachineName,

        [Parameter(Mandatory=$true)]
        $VirtualMachineResourceGroupName,

        $SnapshotId
    )

    $VM = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName

    #PowerState of the machine
    $VMStatus = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName -Status
    $VMPowerState = ($VMStatus.Statuses | Where-Object {$_.code -like "PowerState/*"}).code

    # Record current monitoring setting
    $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VirtualMachine -TagName atosMaintenanceString2 -KeyName MonStatus
    Write-Verbose "Current monitoring status is ${MonitoringSetting}"

    if ($VM) {
        # Get user selected snapshot
        $OSDiskUri = @()
        $OSDiskUri += $VM.StorageProfile.OsDisk.Vhd.Uri

        # Get context from first standard storage account in resource group rather than OsDisk so we can snap VMs with Premium storage too
        $SnapTableStorageContext = Get-StandardStorageContextForResourceGroup -ResourceGroupName $VirtualMachineResourceGroupName

        $SnapInfo = Retrieve-SnapInfo -VirtualMachineName $VirtualMachineName -StorageContext $SnapTableStorageContext
        $UniqueGuids = $SnapInfo | ForEach-Object {$_.SnapGuid} | Sort -Unique

        if ($SnapshotId) {
            $UniqueGuids = $UniqueGuids | Where-Object {$_ -eq $SnapshotId}
        }
        forEach ($Guid in $UniqueGuids) {
            $SnapBlobs = Get-AzureRMVMSnap -VirtualMachineName $VirtualMachineName -SnapshotId $Guid -GetBlobs
            Write-Verbose "VM status = ${VMPowerState}"
            if ($VMPowerState -eq "PowerState/running") {
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
                        $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $$VM
                        break
                    }
                }
            } else {
                Write-Verbose "VM is not running - skipping maintenance mode check"
            }

            #Remove the VM config
            Write-Verbose "Removing the VM configuration..."
            $VM | Remove-AzureRmVm -Force | Out-Null

            forEach ($SnapBlob in $SnapBlobs) {
                $ThisSnap = $SnapInfo | Where-Object {
                    $_.SnapGUID -eq $guid -and `
                    $_.SnapshotUri -eq $SnapBlob.ICloudBlob.SnapshotQualifiedStorageUri.PrimaryUri.AbsoluteUri.ToString()
                }
                Write-Verbose "Reverting disk $($ThisSnap.DiskNum)"
                $DiskInfo = Get-DiskInfoFromUri -DiskUri $SnapBlob.ICloudBlob.Uri.OriginalString
                $OriginalContext = Get-StorageContextForUri -DiskUri $SnapBlob.ICloudBlob.Uri.OriginalString
                $OriginalDiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                                                        -Context $OriginalContext | Where-Object {
                                                            $_.Name -eq $DiskInfo.VHDName -and `
                                                            -not $_.ICloudBlob.IsSnapshot -and `
                                                            $_.SnapshotTime -eq $null
                                                        }
                #$JobId = $OriginalDiskBlob.ICloudBlob.StartCopyAsync($SnapBlob.ICloudBlob)
                $Job = $OriginalDiskBlob.ICloudBlob.StartCopyAsync($ThisSnap.SnapShotUri)
                #TODO: Tidy this up into a function possibly...
                do {
                    $OriginalDiskBlob = Get-AzureStorageBlob -Container $DiskInfo.ContainerName `
                                                            -Context $OriginalContext | Where-Object {
                                                                $_.Name -eq $DiskInfo.VHDName -and `
                                                                -not $_.ICloudBlob.IsSnapshot -and `
                                                                $_.SnapshotTime -eq $null
                                                            }
                    $JobStatus = $OriginalDiskBlob.ICloudBlob.CopyState | Where-Object {$_.CopyId -eq $Job.Result}
                    if ($JobStatus.Status -eq "Success") { break }
                    Write-Verbose "Waiting for snapshot copy... (60s)"
                    Start-Sleep 60
                } until ($CopyStatus -eq "Success")

                Write-Verbose "Copy Complete"
                Write-Verbose "  Completion Time: $($JobStatus.CompletionTime)"
                Write-Verbose "  Bytes Copied: $($JobStatus.BytesCopied)"
            }

            #Remove disallowed settings
            $osType = $VM.StorageProfile.OsDisk.OsType
            $VM.StorageProfile.OsDisk.OsType = $null
            $VM.StorageProfile.ImageReference = $Null
            $VM.OSProfile = $null

            #Old VM Information
            $rgName = $VM.ResourceGroupName
            $locName = $VM.Location
            $osDiskUri = $VM.StorageProfile.OsDisk.Vhd.Uri
            $diskName = $VM.StorageProfile.OsDisk.Name
            $osDiskCaching = $VM.StorageProfile.OsDisk.Caching

            <##Set the OS disk to attach
            #TODO: Replace -windows with correct OS
            $vm=Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskUri -name $DiskName -CreateOption attach -Windows -Caching $osDiskCaching #>

            #Set the OS disk to attach
            #TODO: Replace -windows with correct OS
            Write-Verbose "Attaching the OS disk to Windows VM"
            if ($OsType -like "Windows") {
                $Vm = Set-AzureRmVMOSDisk -VM $Vm -VhdUri $osDiskUri -name $DiskName -CreateOption attach -Caching $osDiskCaching -Windows
            } elseif ($OsType -like "Linux") {
                $Vm = Set-AzureRmVMOSDisk -VM $Vm -VhdUri $osDiskUri -name $DiskName -CreateOption attach -Caching $osDiskCaching -Linux
            }

            #Attach data Disks
            $RevertSnap = $SnapInfo | Where-Object {$_.SnapGUID -eq $Guid -and $_.DiskType -like "DataDisk"}
            if (($RevertSnap.disknum).count -ge 0) {
                Write-Verbose "Configure additional disks"
                $DataDisks = $RevertSnap | Where-Object {$_.DiskType -like "DataDisk"}
                $DiskToBeDeleted = ""
                # Verify if the VM have additional disk which is not there in snap
                if(($VM.StorageProfile.DataDisks).count -gt 0) {
                    forEach($VMDataDisk in $VM.StorageProfile.DataDisks) {
                        $DiskMatched = $False
                        forEach ($DataDisk in $DataDisks) {
                            $SnapDataVHD = (($DataDisk.PrimaryUri).Split("/")).Split(".")[-2]
                            if ($VMDataDisk.Name -like $SnapDataVHD) {
                                $DiskMatched = $true
                            }
                        }
                        if ($DiskMatched -ne $true) {
                            $DiskToBeDeleted = @()
                            $diskvalidation = ""
                            $diskvalidation = Disk-Validation -DiskUri $VMDataDisk.Vhd.Uri -snapinfo $SnapInfo
                            if ($diskvalidation -ne $true) {
                                $DiskToBeDeleted += $VMDataDisk.Vhd.Uri
                            }
                        }
                    }
                }
                Write-Verbose "DiskToBeDeleted : $DiskToBeDeleted"
                $VM.StorageProfile.DataDisks = $Null

                if (($DataDisks.disknum).count -gt 0) {
                    forEach ($DataDisk in $DataDisks) {
                        $VHDName = (($($DataDisk.PrimaryUri)).Split("/")[-1]).split(".")[0]
                        Write-Verbose "-VhdUri $($DataDisk.PrimaryUri)"
                        Write-Verbose "-Name $($VHDName)"
                        Write-Verbose "-Caching $($DataDisk.Caching)"
                        Write-Verbose "-DiskSizeInGB $($DataDisk.DiskSizeGB)"
                        Write-Verbose "-Lun $($DataDisk.Lun)"

                        $VM = Add-AzureRmVMDataDisk -VM $VM -VhdUri $DataDisk.PrimaryUri `
                                                    -Name $VHDName -CreateOption attach `
                                                    -Caching $DataDisk.Caching -DiskSizeInGB $DataDisk.DiskSizeGB `
                                                    -Lun $DataDisk.Lun
                    }
                }
            }
            #If this isn't set the VM will default to Windows and get stuck in the "Updating" state
            #Probably because -windows is set when adding the OS disk!
            Write-Verbose "Setting VM OsType to ${osType}"
            $VM.StorageProfile.OsDisk.OsType = $osType

            $Hwsize = $SnapInfo | Where-Object {$_.SnapGUID -eq $Guid -and $_.DiskType -eq "OSDisk"}
            $VM.HardwareProfile.vmSize = $Hwsize.HardwareProfile
            #Recreate the VM
            Write-Verbose "Recreate the VM..."
            $NewVm = New-AzureRmVM -ResourceGroupName $rgName -Location $locName -VM $VM -WarningAction Ignore

            # Checking the VM PowerState
            $NewVMStatus = Get-AzureRmVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status
            $NewVMPowerState = ($VMStatus.Statuses | Where-Object {$_.code -like "PowerState/*"}).code

            Write-Verbose "New VM powerstate = ${NewVMPowerState}"
            if ($NewVMPowerState -eq "PowerState/running") {
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
                        Write-Verbose "VM is not monitored"
                        break
                    }
                    "MaintenanceMode" {
                        Write-Verbose "Leaving VM in maintenance mode"
                        break
                    }
                    default {
                        Write-Verbose "MonStatus is not set setting to NotMonitored"
                        $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $NewVm
                        break
                    }
                }
            } else {
                Write-Verbose "New VM is not running - skipping monitoring updates"
            }

            #Maintaing the Powerstate of the machine after the snapshot is taken
            if($VMPowerState -eq "PowerState/deallocated")
            {
                Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force | Out-Null
            }

            #Break out of the UniqueGuids loop
            break
        }
    }
    return $DiskToBeDeleted
}

function Test-VmForPremiumStorage {
    Param (
        # An AzureRmVM object to test for premium storage tiers
        [Parameter(Mandatory=$true)]
        [Object]$VirtualMachineObject
    )

    $PremiumAccount = $false

    $StorageAccountNames = @()
    $StorageAccountNames += ($VirtualMachineObject.StorageProfile.OsDisk.Vhd.uri).split('/')[2].split('.')[0]
    forEach ($dataDisk in $VirtualMachineObject.StorageProfile.DataDisks) {
        $StorageAccountNames += $dataDisk.vhd.uri.split('/')[2].split('.')[0]
    }

    $StorageAccountNames | Select-Object -Unique | ForEach-Object {
        $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $VirtualMachineObject.ResourceGroupName -Name $_
        if ($StorageAccount.sku.tier -eq 'Premium') {$PremiumAccount = $true}
    }

    return $PremiumAccount
}

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

    $VirtualMachine = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    if ($VirtualMachine -eq $null) {
        throw "Could not finc VM ${VirtualMachineName} in resource group ${VirtualMachineResourceGroupName}"
    }

    $HasPremiumStorage = Test-VmForPremiumStorage -VirtualMachineObject $VirtualMachine
    if ($HasPremiumStorage) {
        Write-Verbose "VM uses premuim storage"
        # throw "Atos managed snapshots are not currently supported on VMs with premium storage"
    }

    $resultMessage = @()
    # Calling the functions according to the SnapshotAction specified.
    switch ($SnapshotAction) {
        "Create" {
            if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
            if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
            if ([string]::IsNullOrEmpty($SnapshotName)) {throw "Input parameter SnapshotName missing"}
            if ([string]::IsNullOrEmpty($SnapshotDescription)) {throw "Input parameter SnapshotDescription missing"}
            $CreateSnap = New-AzureRMVMSnap -VirtualMachineName $VirtualMachineName `
                                            -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                            -SnapshotName $SnapshotName `
                                            -SnapshotDescription $SnapshotDescription

            $status = "SUCCESS"
            $resultMessage += "Successfully Created the snapshot"
            $resultMessage += "VirtualMachineName : ${VirtualMachineName}"
            $resultMessage += "SnapshotName : ${SnapshotName} $($CreateSnap.SnapshotTime)"
            $resultMessage += "SnapshotDescription : ${SnapshotDescription}"
            $resultMessage += "SnapshotId : $($CreateSnap.SnapshotId)"
        }
        "Delete" {
            if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
            if ([string]::IsNullOrEmpty($SnapshotId)) {throw "Input parameter SnapshotId missing"}

            $DeleteSnap = Delete-AzureRMVMSnap -VirtualMachineName $VirtualMachineName `
                                            -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                            -SnapshotId $SnapshotId
            Write-Verbose "Deleting disk ${DeleteSnap}"
            if (!($DeleteSnap -eq $null -or $DeleteSnap -eq "")) {
                forEach($Disk in $DeleteSnap) {
                    $StorageAcc = ($Disk.Split("/")).split(".")[2]
                    $ContainerName = $Disk.Split("/")[3]
                    $VHDName = $Disk.Split("/")[-1]
                    Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like $StorageAcc} |
                        Get-AzureStorageContainer | Where-Object {$_.name -like $ContainerName} |
                        Remove-AzureStorageBlob -Blob $VHDName -Force
                }
            }

            $status = "SUCCESS"
            $resultMessage += "Successfully Deleted the snapshot"
        }
        "Retrieve" {
            if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
            if ([string]::IsNullOrEmpty($SnapshotId)) {throw "Input parameter SnapshotId missing"}

            Write-Verbose "Reverting snapshot ${SnapshotId}"
            $RetriveSnap = Revert-AzureRMVMSnap -VirtualMachineName $VirtualMachineName `
                                            -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                            -SnapshotId $SnapshotId
            Write-Verbose "Deleting disk ${RetriveSnap}"
            if (!($RetriveSnap -eq $null -or $RetriveSnap -eq "")) {
                forEach ($Disk in $RetriveSnap) {
                    $StorageAcc = ($Disk.Split("/")).split(".")[2]
                    $ContainerName = $Disk.Split("/")[3]
                    $VHDName = $Disk.Split("/")[-1]
                    Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like $StorageAcc} |
                        Get-AzureStorageContainer | Where-Object {$_.name -like $ContainerName} |
                        Remove-AzureStorageBlob -Blob $VHDName -Force
                }
            }

            $status = "SUCCESS"
            $resultMessage += "Successfully Retrived the snapshot"
        }
        default {
            Write-Verbose "${SnapshotAction} SnapshotAction is incorrect"
            throw "${SnapshotAction} SnapshotAction is incorrect"
        }
    }
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage