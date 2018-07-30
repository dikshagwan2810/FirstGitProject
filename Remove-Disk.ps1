#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Script to Remove the data disk.

    .DESCRIPTION
    Script to Remove the managed data disk.
    The script validates whether the data disk is available or not. If available will delete the data disk else it will throw an error.
    The script will delete the data disk from the resource group as well.

    .NOTES
    Author:     Ankita Chaudhari, Austin
    Company:    Atos
    Email:      ankita.chaudhari@atos.net, austin.palakunnel@atos.net
    Created:    2016-12-01
    Updated:    2017-07-27
    Version:    1.2

    .Note 
    Enable the Log verbose records of runbook 
    Refactored to use module
    Edited code to operate on managed disks rather than unmanaged disks.
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
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
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

    $NewDiskName  = $DiskName.Split(".")[0]

    $VMInfo = ""

    if ($VirtualMachineName -ne $null) {
        $VMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName)
        #$VirtualMachineResourceGroupName = $VMInfo.resourcegroup
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        } else {
            Write-Verbose "VM found, proceeding to remove the disk..."
        }
    } 

    #Validating the disk is connected to VM or not
    $DataDiskToBeDeleted = $null
    $DataDisks = $VMInfo.StorageProfile.DataDisks
    foreach ($Disk in $DataDisks) {
        if ($Disk.Name -like $NewDiskName) {
            $DataDiskToBeDeleted = $Disk

        }
    }
    if($DataDiskToBeDeleted -eq $null)
    {
        throw "Disk with name $DiskName not found on VM $VirtualMachineName"
    }

    #Validating the disk is managed or not
    $UnmanagedDiskTest = Get-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $DataDiskToBeDeleted.Name
    if($UnmanagedDiskTest -eq $null)
    {
        throw "This operation cannot be preformed on disk $DiskName as it is an unmanaged disk. This operation is supported only on managed disks."
    }
    else
    {
        Write-Verbose "Managed Disk found can proceed with removing the disk"
    }
    #End of validating disk

    ##Removing data disk from VM  
    $Test = $VMInfo.StorageProfile.DataDisks.Remove($DataDiskToBeDeleted)
    if($Test -eq $false)
    {
        throw "Data disk could not be removed from VM storage profile."
    }
    $UpdateCheck = Update-AzureRmVM -VM $VMInfo -ResourceGroupName $VirtualMachineResourceGroupName
    if($UpdateCheck -eq $null)
    {
        throw "VM profile could not be updated."
    }
    $VMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName)
    $Test1 = $VMInfo.StorageProfile.DataDisks | Where-Object -FilterScript {$_.Name -like $DataDiskToBeDeleted.Name}
    if($Test1 -ne $null)
    {
        throw "Data disk could not be removed from VM storage profile."
    }
    ##End of remove data disk from VM


    #Removing Data Disk
    $RemoveResult = Remove-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $DataDiskToBeDeleted.Name -Force
    if ($RemoveResult.Status -eq 'Succeeded')
    {
        Write-Verbose "Successfully removed disk $($DataDiskToBeDeleted.Name)"
    }
    else
    {
        throw "Failed to remove disk $($DataDiskToBeDeleted.Name) with status $($RemoveResult.Status) and ID $($RemoveResult.Name)"
    }

    #End of Removing Data Disk from Resourcegroup

    $status = "SUCCESS"
    $resultMessage = "Successfully deleted the Data Disk $($DataDiskToBeDeleted.Name)"
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
