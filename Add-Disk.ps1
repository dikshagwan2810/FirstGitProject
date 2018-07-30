#Requires -Modules Atos.RunbookAutomation

<#
    .SYNOPSIS
    This script adds new disk to existing Virtual Machine.
  
    
    .DESCRIPTION
    - Performs addition of standard and premium disk to VM.
    - Performs check by verifying the maximum number of disk attached to existing hardware profile VM.
    - The script will append the machine name with the disk name. 
    
    
    .NOTES
    Author:     Rashmi Kanekar,Ankita Chaudhari
    Company:    Atos
    Email:      rashmi.kanekar@atos.net,ankita.chaudhari@atos.net
    Created:    2016-11-30
    Updated:    2017-05-04
    Version:    1.2
    
    .Note 
    1.0 - Enable the Log verbose records of runbook
    1.1 - Updated to use module and harmonise parameters
    1.2 - Add VMname to DiskName and append with counter if disk name is already taken
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

    # The name for the new disk.  This will be combined with the VM name, and a counter if necessary, to ensure a unique name
    [Parameter(Mandatory=$true)] 
    [String] 
    $DiskName,

    # The size of the new disk in GB
    [Parameter(Mandatory=$true)] 
    [int] 
    $DiskSizeInGb,

    # Set true to use premium storage instead of standard storage
    [Parameter(Mandatory=$true)] 
    [Boolean]
    $UsePremiumStorage,

    # The caching type required.  One of None, ReadOnly, ReadWrite
    [Parameter(Mandatory=$true)] 
    [ValidateSet('None', 'ReadOnly', 'ReadWrite')]
    [String] 
    $HostCachingType,

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
    if ([string]::IsNullOrEmpty($DiskName)) {throw "Input parameter DiskName missing"} 
    if ([string]::IsNullOrEmpty($DiskSizeInGb)) {throw "Input parameter DiskSizeInGb missing"} 
    if ([string]::IsNullOrEmpty($UsePremiumStorage)) {throw "Input parameter UsePremiumStorage missing"} 
    if ([string]::IsNullOrEmpty($HostCachingType)) {throw "Input parameter HostCachingType missing"} 
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

    $HwProfile = $VmInfo.HardwareProfile.VmSize 
    # Performing Storage Checks 
    if ($UsePremiumStorage -eq $true) {
        $StorageType = "PremiumLRS"
        if (!($(($HwProfile.Split("_")[1]).ToUpper()).Contains("S"))) {
            # Premium Profile
            throw "Existing VM profile is standard so premium disk cannot be attached."
        }
    } 
    else {
        $StorageType = "StandardLRS"
    }

    $VmLocation = $VmInfo.Location
    $DefaultSizeInfo = Get-AzureRmVMSize -Location $VmLocation | Where-Object {$_.Name -like "$HwProfile"}
    
    Write-Verbose "Validating the disk check according to the hardware profile"
    if ($DefaultSizeInfo.MaxDataDiskCount -le $VmInfo.StorageProfile.DataDisks.Count) {
        throw "OperationNotAllowed: The maximum number of data disks allowed to be attached to a VM of this size is $($DefaultSizeInfo.MaxDataDiskCount)"
    }
    if ([int]$DiskSizeInGb -gt 4095) {
        Throw "OperationNotAllowed: The Entered disk Size exceeds Max Size 4095GB"
    }

    $StorageCheck = $false
    $LunCount = 0
    $DataDiskList = $VmInfo.StorageProfile.DataDisks
    while ($StorageCheck -eq $false) {
        $OperationTest = ""
        $OperationTest = $DataDiskList | Where-Object {$_.Lun -eq $LunCount}
        if ($OperationTest -eq $null) {
            $StorageCheck = $true
            Break
        }
        $LunCount++
    }
    Write-Verbose "Next available lun for disk placement : ${LunCount}"

    Write-Verbose "Checking for existing disk with the same name"
    $DiskName = "$($VMInfo.Name)-${DiskName}"
    $ExistingDiskName = Get-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName | Select-Object -ExpandProperty name
    foreach($Disks in $ExistingDiskName)
    {
        if($DiskName -like $Disks)
        {
            throw "Disk Name $DiskName already exists. Kindly specify a new name"
        }
    }

    # Adding Storage 
    Write-Verbose "Performing Adding of Disk on VM: ${VirtualMachineName}"
   
    $ExistingDiskCount = $VmInfo.StorageProfile.DataDisks.Count
    
    $DiskConfig = New-AzureRmDiskConfig -AccountType $StorageType -Location $VmLocation -CreateOption Empty -DiskSizeGB $DiskSizeInGb

    $DataDisk1 = New-AzureRmDisk -DiskName $DiskName -Disk $DiskConfig -ResourceGroupName $VirtualMachineResourceGroupName

    $VM = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName 

    $Operation = Add-AzureRmVMDataDisk -VM $VM -Name $DiskName -CreateOption Attach -ManagedDiskId $DataDisk1.Id -Lun $LunCount -Caching $HostCachingType

    $Operation1 = Update-AzureRmVM -VM $VM -ResourceGroupName $VirtualMachineResourceGroupName
   
    $NewVmInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    if ($ExistingDiskCount -lt $NewVmInfo.StorageProfile.DataDisks.Count) {
        $resultMessage = "Disk: ${DiskName} was successfully added with Size: ${DiskSizeInGb} Gb on VM: ${VirtualMachineName}"
    }
    
    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
