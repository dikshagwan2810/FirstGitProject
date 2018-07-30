#Requires -Modules Atos.RunbookAutomation
<#
	.SYNOPSIS
    This script converts Unmanaged VM to Managed VM.
	
	.DESCRIPTION
    Performs conversion of the Virtual Machine from Unmanged to Managed along it's the OS Disk and Data Disks. 
	
	.NOTES
    Author: 	Krunal Merwana
    Company:	Atos
    Email:  	krunal.merwana@atos.net
    Created:	2017-08-02
    Updated:	0000-00-00
    Version:	1.0
	
	.Note
    1.0 - Conversion of Unmanaged VM to Managed VM
#>

param(
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    # The name of the VM to act upon
    [Parameter(Mandatory=$false)]
    [String]
    $VirtualMachineName = $null
    
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


try {  
    # Input Validation
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."} 
    
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
    
    #Gather VM Info
    if($VirtualMachineName -ne "") {
        Write-Verbose "Retrieving VM: ${VirtualMachineName}"
        $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        $VmInfoStatus = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        }
    }
    else{
        Write-Verbose "Retrieving Virtual Machines from ${VirtualMachineResourceGroupName}"
        $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM's not found in Resource Group ${VirtualMachineResourceGroupName}"
        }
    }

    $status = "SUCCESS"
    $resultMessage = ""

    #Convert Unmanaged VM to Managed VM
    foreach($VM in $VMInfo){
        $VMName = $VM.Name        
        if ($VM.ProvisioningState -ne 'Succeeded') {
            $status = "FAILURE"
            $resultMessage += "`nVM: ${VMName} failed to convert as it's provisioning state is $($VM.ProvisioningState)"
        } else {
            $failedExtensions = $null
            $failedExtensions = $VM.Extensions | Where-Object {$_.ProvisioningState -eq 'Failed'}
            if ($failedExtensions -ne $null) {
                $failedExtensionInfo = @()
                forEach ($extension in $failedExtensions) {
                    $failedExtensionInfo += "`nExtension $($extension.Name) is in state $($extension.ProvisioningState)"
                }
                $resultMessage += "`nVM: ${VMName} failed to convert because $($failedExtensionInfo -join ", ")"
            } elseif ($VM.StorageProfile.OsDisk.ManagedDisk -eq $null){        
                try {
                    #Gather VHD Disk Blobs
                    Write-Verbose "Gathering VHD Disk blobs for ${VMName}"
	                $VHDList = @()
	                $VHDList += $VMInfo.StorageProfile.OsDisk.Vhd.Uri
	                    forEach ($Vhd in ($VMInfo.StorageProfile.DataDisks.vhd.Uri)) {
		                $VHDList += $Vhd
	                }
                    Write-Verbose "Retrieved VHD List: ${VHDList}"         
                    
                    #Checking If the VM contains the Snapshot and deletes the snapshot
                    Write-verbose "Checking if ${VMName} contains snapshots."
                    $Snapcheck = Get-AzureRMVMSnap -VirtualMachineName $VMName
                    $SnapshotId = $Snapcheck.SnapGUID
                    $SnapshotName = $Snapcheck.SnapshotName
                    if (!($Snapcheck -eq $null -or $Snapcheck -eq "")) {
                        Write-Verbose "Deleting the snapshot ${SnapshotName}"
                        $DeleteSnap = Delete-AzureRMVMSnap -VirtualMachineName $VMName `
                                            -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                            -SnapshotId $SnapshotId
                    }

                    #Converting the Vm From Unmanaged Disks to Managed Disks
                    Write-Verbose "Converting ${VMName} Vm from Unmanaged to Managed VM"
                    $StopVMStatus = Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VMName -Force
                    $ConvertVMStatus = ConvertTo-AzureRmVMManagedDisk -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VMName
                    $resultMessage += "`nVM: ${VMName} Converted successfully."

                    # Remove VHD Blobs
	                forEach ($VHD in $VHDList) {
		                $StorageAcc = $Vhd.Split("/").split(".")[2]
		                $VHDName = $Vhd.Split("/")[-1]
		                $ContainerName =  $Vhd.Split("/")[-2] 
		                Write-Verbose "Removing VHD ${VHDName} from account ${StorageAcc} container ${ContainerName}"
		                Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "$StorageAcc"} |
			            Get-AzureStorageContainer | Where-Object {$_.name -like "$ContainerName"} |
			            Remove-AzureStorageBlob -Blob $VHDName | Out-Null
	                }
                } catch {
                    $status = "FAILURE"
                    $resultMessage += "`nVM: ${VMName} failed to convert due to: "
                    $resultMessage += $_.ToString().Split("`n")[0]
                }
            } else {
                $resultMessage += "`nVM: ${VMName} was not converted as it is already using managed disks."
            }
        }          
    }

} catch {
    $status = "FAILURE"
    $resultMessage += $_.ToString()
}

Write-Output $status
Write-Output $resultMessage