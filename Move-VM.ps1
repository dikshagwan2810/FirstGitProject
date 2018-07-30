#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Script to move Managed VM between regions.

    .DESCRIPTION
    Moves the Managed VM from one region to another region.
    The script will create new public IP and also network interface for the Managed VM in new region.
    The script will remove the Managed VM along with the resources from the old location.

    .NOTES
    Author:     Ankita Chaudhari & Arati Chakravarti
    Company:    Atos
    Email:      ankita.chaudhari@atos.net, arati.chakravarti@atos.net
    Created:    2017-01-24
    Updated:    2017-08-30
    Version:    1.4

    .Note
    1.0 - Enable the Log verbose records of runbook
    1.1 - Refactored to use module and harmonise parameters
    1.2 - Skip snapshot check if premium storage found
    1.3 - Re-enable snapshot check for premium storage VMs
    1.4 - Operation now supports only Managed Virtual Machines
#>

Param (
    #The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    #The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    #The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    #The Destination Resource Group to move the VM to
    [Parameter(Mandatory=$true)]
    [String]
    $DestinationVirtualMachineResourceGroupName,

    #The Destination Virtual Network Resource Group
    [Parameter(Mandatory=$true)]
    [String]
    $DestinationVirtualNetworkResourceGroupName,

    #The Destination Virtual Network name
    [Parameter(Mandatory=$true)]
    [String]
    $DestinationVirtualNetworkName,

    #The Destination Subnet name
    [Parameter(Mandatory=$true)]
    [String]
    $DestinationVirtualNetworkSubnetName,

    #The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    #The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)



 try {
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter RequestorUserAccount missing"}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter ConfigurationItemId missing"}
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter SubscriptionId missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VirtualMachineName missing"}
    if ([string]::IsNullOrEmpty($DestinationVirtualMachineResourceGroupName)) {throw "Input parameter DestinationVirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($DestinationVirtualNetworkResourceGroupName)) {throw "Input parameter DestinationVirtualNetworkResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($DestinationVirtualNetworkName)) {throw "Input parameter DestinationVirtualNetworkName missing"}
    if ([string]::IsNullOrEmpty($DestinationVirtualNetworkSubnetName)) {throw "Input parameter DestinationVirtualNetworkSubnetName missing"}

    #Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

     Write-Verbose "Retrieve runbook objects"
    #Set the $Runbook object to global scope so it's available to all functions
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    #FINISH management subscription code

    #Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    [string] $resultMessage = ""
    $VMInfo = ""

    $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    if ($VMInfo -eq $null -or $VMInfo -eq "") {
        throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
    } else {
        Write-Verbose "VM found can proceed to move"
    }

    #Check whether Vm is managed or not
    if($VMInfo.StorageProfile.OsDisk.ManagedDisk -eq $null)
    {
        throw "The VM is unmanaged"
    }

    if($VMInfo.AvailabilitySetReference.Id -ne $null)
    {
              throw "VM : ${VirtualMachineName} Can Not be Moved because it's in availability set."
    }

    #Checking the machine PowerState
    $VMStatusCheck = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status |  Select-Object -ExpandProperty Statuses
    $VMStatus = $VMStatusCheck[1].Code
    if($VMStatus -eq "PowerState/Running")
    {
        throw "VM : ${VirtualMachineName} is in running state. Please stop(Deallocate) the VM ${VirtualMachineName} to perform move operation."
    }
    elseif($VMStatus -eq "PowerState/Stopped")
    {
        throw "VM : ${VirtualMachineName} is in Stopped state. Please stop(Deallocate) the VM ${VirtualMachineName} to perform move operation."
    }

    #Get the Monitoring tag value
    $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VMInfo -TagName "atosMaintenanceString2" -KeyName "MonStatus"
    if($MonitoringSetting -eq "" -or $MonitoringSetting -eq $null)
    {
        Write-Verbose "Setting Monitoring Tag value to NotMonitored"
        $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $VMInfo -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue "NotMonitored"
        $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VMInfo -TagName "atosMaintenanceString2" -KeyName "MonStatus"
    }

    $DestRGCheck = Get-AzureRmResourceGroup -Name $DestinationVirtualMachineResourceGroupName
    if ($DestRGCheck -eq $null) {
        throw "The Resource Group ${DestinationVirtualMachineResourceGroupName} not found"
    }

    #Getting the Destination location
    $DestinationLocation = $DestRGCheck.Location
    Write-Verbose "DestinationLocation: ${DestinationLocation}"

    #Checking the destination virtual network and subnet
    $DestVnet = Get-AzureRmVirtualNetwork -ResourceGroupName $DestinationVirtualNetworkResourceGroupName -Name $DestinationVirtualNetworkName
    if ($DestVnet -eq $null) {
        throw "Cannot find destination Virtual Network '${DestinationVirtualNetworkName}' in Resource Group '${DestinationVirtualNetworkResourceGroupName}'"
    }
    $DestSubnetid = ($DestVnet.Subnets | Where-Object {$_.name -like $DestinationVirtualNetworkSubnetName }).id
    if ($DestSubnetId -eq $null) {
        throw "Cannot find destination Subnet '${DestinationVirtualNetworkSubnetName}' in destination Virtual Network '${DestinationVirtualNetworkName}'"
    }

    Write-Verbose "Gathering the information"
    #Gathering the source VM info
    $SourceOsCaching = $VMInfo.StorageProfile.OsDisk.Caching
    $SourceOSDiskURI = $VMInfo.StorageProfile.OsDisk.ManagedDisk.Id
    $OSDiskName = $SourceOSDiskURI.Split("/")[-1]

    Write-Verbose "Copying Data Disk"
   
    #Copying Data Disk       
    forEach ($disk in $VMInfo.StorageProfile.DataDisks) {
        Write-Verbose  "Inside forEach loop"
        $DataDiskId = $disk.ManagedDisk.Id
        $DataDiskName = $DataDiskId.Split('/')[-1]
        $DataDiskInfo = Get-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $DataDiskName
        $DataDiskstorageType = $DataDiskInfo.Sku.Name
      
        #Get the source Data Disk Configuration
        $diskConfig = New-AzureRmDiskConfig -SourceResourceId $DataDiskInfo.Id -Location $DataDiskInfo.Location -CreateOption Copy 
        
        #Create a new managed disk in the target subscription and resource group
        $NewDataDiskInfo = New-AzureRmDisk -Disk $diskConfig -DiskName $DataDiskName -ResourceGroupName $DestinationVirtualMachineResourceGroupName
    }   
       

    #Copying OS Disk
    Write-Verbose  "Copying OS Disk"
    $OSDiskURI = $VMInfo.StorageProfile.OsDisk.ManagedDisk.Id
    $OSDiskName = $OSDiskURI.Split('/')[-1]
    $OSDiskInfo = Get-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $OSDiskName
    $OSstorageType = $OSDiskInfo.Sku.Name
    
    Write-Verbose "OSstorageType: $OSstorageType"   
    Write-Verbose "Get the source OS Disk Configuration"
    $diskConfig = New-AzureRmDiskConfig -SourceResourceId $OSDiskInfo.Id -Location $OSDiskInfo.Location -CreateOption Copy 
        
    Write-Verbose "Create a new managed disk in the target subscription and resource group"
    $NewOSDiskInfo = New-AzureRmDisk -Disk $diskConfig -DiskName $OSDiskName -ResourceGroupName $DestinationVirtualMachineResourceGroupName
    
    
    Write-Verbose "Checking for a public IP address on the source VM"
    $hasPublicIp = $False
    forEach ($NetworkInterface in $VMInfo.NetworkProfile.NetworkInterfaces) {
        $NicIdParts = ($NetworkInterface.ID).Split('/')
        $Nic = Get-AzureRmNetworkInterface -ResourceGroupName $NicIdParts[-5] -Name $NicIdParts[-1]
        forEach ($IpConfig in $Nic.IpConfigurations) {
            if ($IpConfig.PublicIpAddress -ne $null) {
                Write-Verbose "Found source public IP address"
                $hasPublicIp = $true
            }
        }
    }

    if ($hasPublicIp -eq $true) {
        Write-Verbose  "Creating destination NIC with a new public IP address"
        $DestNewPublicIp = New-AzureRmPublicIpAddress -Name "${VirtualMachineName}pip0" -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation -AllocationMethod Dynamic -Force
        $DestNewNIC = New-AzureRmNetworkInterface -Name "${VirtualMachineName}nic0" -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation -Subnetid $DestSubnetid -PublicIpAddressId $DestNewPublicIp.Id -Force
    } else {
        Write-Verbose  "Creating destination NIC"
        $DestNewNIC = New-AzureRmNetworkInterface -Name "${VirtualMachineName}nic0" -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation -Subnetid $DestSubnetid -Force
    }

    #Remove VM from source location
    #Connect to the management subscription and call child runbook
    $ManagementContext = Connect-AtosManagementSubscription
    $Params = @{
          "VirtualMachineResourceGroupName" = $VirtualMachineResourceGroupName
          "VirtualMachineName" = $VirtualMachineName
          "RemoveChildResources" = $true
          "RequestorUserAccount" = $RequestorUserAccount
          "ConfigurationItemId" = $ConfigurationItemId
          "SubscriptionId" = $SubscriptionId
    }
    $RemoveVMOutput = Start-AzureRmAutomationRunbook -AutomationAccountName $Runbook.AutomationAccount  -Name "Remove-VM" -ResourceGroupName $Runbook.ResourceGroup -Parameters $Params -Wait

    #Switch to customer's subscription context and create new VM
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    #Initialize virtual machine configuration
    $VirtualMachine = New-AzureRmVMConfig -VMName $virtualMachineName -VMSize $VMInfo.HardwareProfile.VmSize

    #Use the Managed Disk Resource Id to attach it to the virtual machine. Please change the OS type to linux if OS disk has linux OS
    $OsType = $VMInfo.StorageProfile.OsDisk.OsType

    if($OsType -like "Windows")
    {
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $NewOSDiskInfo.Id -CreateOption Attach -Windows
    } 
    
    elseif($OsType -like "Linux")
    { 
        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $NewOSDiskInfo.Id -CreateOption Attach -Linux
    }

    #Create a public IP for the VM  
    $publicIp = New-AzureRmPublicIpAddress -Name ($VirtualMachineName.ToLower()+'_ip') -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation -AllocationMethod Dynamic

    #Get the virtual network where virtual machine will be hosted
    $vnet = Get-AzureRmVirtualNetwork -Name $DestinationVirtualNetworkName -ResourceGroupName $DestinationVirtualNetworkResourceGroupName

    #Create NIC in the first subnet of the virtual network 
    $nic = New-AzureRmNetworkInterface -Name ($VirtualMachineName.ToLower()+'_nic') -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation -SubnetId $DestSubnetid -PublicIpAddressId $publicIp.Id

    $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

    #Create the virtual machine with Managed Disk
    $NewVmInfoStatus = New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Location $DestinationLocation
    if( $NewVmInfoStatus.IsSuccessStatusCode -ne $true ){
    
        throw "Failed to re-create VM ${VirtualMachineName} in new location ${DestinationLocation}. The status of newly created VM is $($NewVmInfoStatus.Status), $($NewVmInfoStatus.StatusCode)"
     }

    $NewVmInfo = Get-AzureRmVM -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Name $virtualMachineName
    $NewVMStatusCheck = Get-AzureRmVM -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Name $VirtualMachineName -Status |  Select-Object -ExpandProperty Statuses
    $NewVMStatusCheck = $NewVMStatusCheck[1].Code

    if($NewVMStatusCheck -eq "PowerState/Running")
    {
       $StopNewVmInfo = Stop-AzureRmVM -Name $NewVmInfo.Name -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Force
    }
    
    #Adding The Data Disk in New VM
    forEach ($DiskInfo in  $VMInfo.StorageProfile.DataDisks) {
        $NewDataDiskss = Get-AzureRmDisk -DiskName $DiskInfo.Name -ResourceGroupName $DestinationVirtualMachineResourceGroupName
        Write-Verbose "Disk Info $NewDataDiskss"

        $DataDiskId =  $NewDataDiskss.Id
        Write-Verbose "DIsk ID $DataDiskId"

        Write-Verbose "Adding Existing Disk Name : $($NewDataDiskss.name) on LUN $($DiskInfo.Lun) of Size : $($NewDataDiskss.DiskSizeGB)"
        Add-AzureRMVMDataDisk -ManagedDiskId $DataDiskId -Lun $DiskInfo.Lun  -CreateOption Attach -DiskSizeInGB $NewDataDiskss.DiskSizeGB -VM $NewVmInfo -Name $($NewDataDiskss.name) | Out-Null

        Write-Verbose "Updating VM"
        Update-AzureRmVM -ResourceGroupName $DestinationVirtualMachineResourceGroupName -VM $NewVmInfo | Out-Null

        Write-Verbose "After Adding Disk"
        $VMDisk = $NewVmInfo.StorageProfile.DataDisks

  }

    #Setting the diagnosticsboot storageuri
    $SourceBootStorageURI = $VMInfo.DiagnosticsProfile.BootDiagnostics.StorageUri
    $BootStorageAccount = ($SourceBootStorageURI.Split("/").Split("."))[2]
    $DestinationBootStorageURI = $SourceBootStorageURI.Replace("$BootStorageAccount", "$($StandardDestStorageAccount.StorageAccountName)")
    $VMInfo.DiagnosticsProfile.BootDiagnostics.StorageUri = $null
    $VMInfo.DiagnosticsProfile.BootDiagnostics.StorageUri = $DestinationBootStorageURI

  
    #Checking the Value of Monitoring Tag for newly created VM
    $NewVMTagValue = Get-AtosJsonTagValue -VirtualMachine $NewVMInfo -TagName "atosMaintenanceString2" -KeyName "MonStatus"
    if($MonitoringSetting -ne $NewVMTagValue)
    {
        #Setting the Monitoring Tag value
        Write-Verbose "Setting Monitoring Tag value"
        $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $NewVMInfo -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue $MonitoringSetting
        Write-Verbose "Stopping Virtual machine $VirtualMachineName"
        $StopVM = Stop-AzureRmVM -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Name $VirtualMachineName -Force
    }
    else
    {
        Write-Verbose "Stopping virtual machine $VirtualMachineName"
        $StopVM = Stop-AzureRmVM -ResourceGroupName $DestinationVirtualMachineResourceGroupName -Name $VirtualMachineName -Force
    }

    if (($NewVMInfo -ne $null) -or ($NewVMInfo -ne "")) {
        $status = "SUCCESS"
        $resultMessage = "Successfully moved VM ${VirtualMachineName} to new location ${DestinationLocation}"
    } else {
        $status = "FAILURE"
        $resultMessage = "Failed to re-create VM ${VirtualMachineName} in new location ${DestinationLocation}"
    }
} catch 
    {
        $status = "FAILURE"
        $resultMessage = $_.ToString()
    }

Write-Output $status
Write-Output $resultMessage