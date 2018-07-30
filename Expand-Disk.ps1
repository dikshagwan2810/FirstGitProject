#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Script to Expand the Disk size with Managed Disk.

    .DESCRIPTION
    Script to Expand the Disk size with Managed Disk.
    -Epands only the Data Diks attched to the VM
    -Can expand the Data Disk only uptill 4TB

    .NOTES
    Author:   Abhijit Pawar
    Company:  Atos
    Email:    abhijit.pawar@atos.net
    Created:  2017-08-01
    Updated:  2017-00-00
    Version:  1.1

    .Note 
    Enable the Log verbose records of runbook 
    The size to be expanded should be in GB.
    Mention the total(new) size to be expanded.
#>

Param (
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

    # The size in GB for the new disk. This must be larger than the existing disk.
    [Parameter(Mandatory=$true)] 
    [Int] 
    $DiskSizeInGb,

    # The full name of the disk to be expanded. i.e. DataDisk01.vhd
    [Parameter(Mandatory=$true)] 
    [String] 
    $DiskName,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

try {
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
    if ([string]::IsNullOrEmpty($DiskSizeInGb)) {throw "Input parameter DiskSizeInGb missing"}
    if ([string]::IsNullOrEmpty($DiskName)) {throw "Input parameter DiskName missing"}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter RequestorUserAccount missing"}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter ConfigurationItemId missing"}

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

    $VMInfo = ""
    $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
        throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
    } else {
        Write-Verbose "VM found can proceed"
    }

    #Checking if the VM is managed or unmanaged
    if ($VMInfo.StorageProfile.OsDisk.ManagedDisk -eq $null)
    {
        throw "VM : ${VirtualMachineName} does not contain managed disk."
    
    } 
    #Validating whether the machine is in off state
    $TempVMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status)
    $VMStatus = ($TempVMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code
    Write-Verbose "Status of VM is ${VMStatus}"
    if ($VMStatus -like "PowerState/Running") {
        throw "Expand disk operation can be performed only when the machine is in deallocated state. Kindly deallocate the machine and perform the operation."
    } elseif ($VMStatus -like "PowerState/stopped") {
        throw "Expand disk operation can be performed only when the machine is in deallocated state. Kindly deallocate the machine and perform the operation."
    }
    #End of validation

    #Validating the Disk Size
    #$Disk = $DiskName.Split(".")[0]
    $CurrentDiskSize = $VMInfo.StorageProfile.DataDisks | Where-Object {$_.Name -like $DiskName} | Select-Object -ExpandProperty DiskSizeGB
    if ($DiskSizeInGb -lt $CurrentDiskSize -or $DiskSizeInGb -eq $CurrentDiskSize) {
        throw "Kindly enter the size greater than ${CurrentDiskSize} GB"
    }

    [int]$MaxDiskSize = 4095
    if ($DiskSizeInGb -gt $MaxDiskSize) {
        throw "Data Disk ${DiskName} can be expanded to a maximum size of 4095GB"
    }
    #End of validating the Disk Size

    #Validating the disk is available or not
    $DiskInfo = Get-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $DiskName
    
    if ($DiskInfo -eq $null -or $DiskInfo -eq "") {
        throw "Disk with name ${DiskName} not found"
    } else {
        Write-Verbose "Disk found can proceed with expanding"
    }

    #End of validating disk

    # Set the new disk size
    $DiskUpdateConfig = New-AzureRmDiskUpdateConfig -DiskSizeGB $DiskSizeInGb

    #Expanding the Disk Size
    Write-Verbose "Expanding Disk size."
        $UpdateStatus = Update-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $DiskName -DiskUpdate $DiskUpdateConfig
        if($UpdateStatus.ProvisioningState -like "Succeeded")
        {
            $status = "SUCCESS"
            $resultMessage = "Successfully Expanded the disk ${DiskName} to size $DiskSizeInGb"
        }
   else{
        $status = "FAILURE"
        $resultMessage = "Failed to Expand Disk Size on Disk ${DiskName} for VM ${VirtualMachineName} due to "
        $resultMessage += $_.ToString()
        }
    
    #End of Expanding the Disk Size
        
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
