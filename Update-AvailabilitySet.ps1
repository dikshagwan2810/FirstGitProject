#Requires -Modules Atos.RunbookAutomation

<#
    .SYNOPSIS
    This script removes the Virtual Machine from the Availability Set.
    
    .DESCRIPTION
    - Performs removing of virtual machine from the availability set.
    - Performs check by verifying if the machine belongs to the availability set.
    
    .NOTES
    Author:     Ankita Chaudhari
    Company:    Atos
    Email:      ankita.chaudhari@atos.net
    Created:    2017-08-24
    Version:    1.0
    
    .Note 
    1.0 - Enable the Log verbose records of runbook
    1.1 - Updated to use module and harmonise parameters
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')] [ValidateNotNullOrEmpty()]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    # The name of the Availability Set that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $AvailabilitySetName,

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
    # Input Validation
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter SubscriptionId missing"} 
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"} 
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"} 
    if ([string]::IsNullOrEmpty($AvailabilitySetName)) {throw "Input parameter AvailabilitySetName missing"} 
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

    # Performing Resource Group Check
    Write-Verbose "Performing Resource Group Check for resource group ${VirtualMachineResourceGroupName}"
    $ResourceGroupInfo = Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName
    if ($ResourceGroupInfo -eq $null) {
        throw "Resource Group Name ${VirtualMachineResourceGroupName} not found"
    }

    # Retrieving VM information
    Write-Verbose "Retrieving VM information for Vm: ${VirtualMachineName} of ResourceGroup: ${VirtualMachineResourceGroupName}"
    $VmInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName 
    if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
        throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
    }
    
    #Check if the VM is managed or unmanaged
    $ManagedDisk = $VmInfo.StorageProfile.OsDisk.ManagedDisk.Id
    if($ManagedDisk -eq "" -or $ManagedDisk -eq $null)
    {
        throw "The Virtual Machine $VirtualMachineName contains unmanaged disks. Kindly select a VM which has Managed Disks."
    }

    #Check if the Availability Set exists or not


    #Check if the VM is the part of an Availability Set and Availability Set exists or not
    $VMASName = $VMInfo.AvailabilitySetReference.Id
    $GetAvailabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $VirtualMachineResourceGroupName -Name $AvailabilitySetName -ErrorAction SilentlyContinue
    if($GetAvailabilitySet -eq "" -or $GetAvailabilitySet -eq $null)
    {
        throw "AvailabilitySetName: $AvailabilitySetName does not exist."
    }
    $ID = $GetAvailabilitySet.Id
    if(!($VMASName -eq $ID))
    {
        throw "Virtual machine $VirtualMachine is not a part of $AvailabilitySet"
    }

    $VMvnicName = ($VmInfo.NetworkProfile.NetworkInterfaces.id).split("/")[-1]
    $nic = Get-AzureRmNetworkInterface -Name $VMvnicName -ResourceGroupName $VirtualMachineResourceGroupName

    $LoadBalancerConfig = $nic.IpConfigurations[0].LoadBalancerBackendAddressPools
    if($LoadBalancerConfig.Id -ne $null)
    {
        throw "Virtual Machine is part of Load  Balancer: $($LoadBalancerConfig.Id).  Please remove Virtual machine from load balancer and retry this operation."
    }
    
    #Gathering OS and Data Disk information
    #For OS Disk
    $OSDIskInfo = $VMInfo.StorageProfile.OsDisk
    $OSType = $OSDIskInfo.OsType
    $OSDiskName = $OSDIskInfo.Name
    $OSCache = $OSDIskInfo.Caching
    $OSDiskID = $VMInfo.StorageProfile.OsDisk.ManagedDisk.Id
    $OSDiskSizeGB = $OSDIskInfo.DiskSizeGB
    $VMOSProfile = $VMInfo.OSProfile

    #Removing the Old VM config
    $VMInfo.OSProfile = $null
    $VMInfo.StorageProfile.OsDisk.ManagedDisk.Id = $null
    $VMInfo.StorageProfile.OsDisk = $null

    #Attaching OS disk to the VM as per the OSType
    if ($OSType -like "Windows") 
    {
       $WindowsVM = Set-AzureRmVMOSDisk -VM $VMInfo -Name $OSDiskName -Caching $OSCache -ManagedDiskId $OSDiskID -CreateOption Attach -Windows -DiskSizeInGB $OSDiskSizeGB
    } 
    elseif ($OSType -like "Linux") 
    {
       $LinuxVM = Set-AzureRmVMOSDisk -VM $VMInfo -Name $OSDiskName -Caching $OSCache -ManagedDiskId $OSDiskID -CreateOption Attach -Linux -DiskSizeInGB $OSDiskSizeGB
    }

    #For Data Disks
    $DataDisks = $VmInfo.StorageProfile.DataDisks
    $VmInfo.StorageProfile.DataDisks = $null
    foreach($Disks in $DataDisks)
    {
        $DataDiskName = $Disks.Name
        $DataDiskSize = $Disks.DiskSizeGB
        $DataDiskLUN = $Disks.Lun
        $DataDiskCaching = $Disks.Caching

        #Attaching exsisting Data Disk to VM
        $DiskInfo = Get-AzureRmDisk -DiskName $DataDiskName -ResourceGroupName $VirtualMachineResourceGroupName
        Add-AzureRmVMDataDisk -VM $VmInfo -Name $DataDiskName -CreateOption Attach -Lun $DataDiskLUN -Caching $DataDiskCaching -DiskSizeInGB $DataDiskSize -ManagedDiskId $DiskInfo.Id | Out-Null
    }

    #Remove VM from an Availability Set
    $VMInfo.AvailabilitySetReference = $null
    $VMInfo.StorageProfile.ImageReference = $null
    $VMInfo.OSProfile = $null

    #Removing the VM which is in Availability Set
    Remove-AzureRmVM -Name "$VirtualMachineName" -ResourceGroupName "$VirtualMachineResourceGroupName" -Force | Out-Null

    #Re-creating the VM to remove it from Availability Set
    New-AzureRmVM -ResourceGroupName "$VirtualMachineResourceGroupName" -VM $VMInfo -Location $($VMInfo.Location) | Out-Null

    $NewVmInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    $ASValue = $NewVmInfo.AvailabilitySetReference
    if ($ASValue -eq $null -or $ASValue -eq "") {
        $resultMessage = "Virtual Machine $VirtualMachineName successfully removed from Availability Set $AvailabilitySetName"
    }
    
    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage