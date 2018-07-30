#Requires -Modules Atos.RunbookAutomation
<#
	.SYNOPSIS
    This script deletes the Virtual Machine along with VHD's.
	
	.DESCRIPTION
    Performs deletion of Virtual Machine along with the deletion of additional resources like VNIC,IP,NSG. 
	
	.NOTES
    Author: 	Krunal Merwana
    Company:	Atos
    Email:  	krunal.merwana@atos.net
    Created:	2016-11-24
    Updated:	2017-08-02
    Version:	1.4
	
	.Note
    1.0 - Enable the Log verbose records of runbook
    1.1 - Refactored to use module and harmonise parameters
    1.2 - Skip snapshot check if premium storage found
    1.3 - Re-enable snapshot check for premium storage VMs
    1.4 - Supports only for Managed VM and deletion of it's Managed disks.
#>

param(
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

    # Set true to remove all child resources
	[Parameter(Mandatory=$True)]
	[Boolean]
	$RemoveChildResources,

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
	if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."} 
	if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."} 
	if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter: VirtualMachineName missing."} 
	if ([string]::IsNullOrEmpty($RemoveChildResources)) {throw "Input parameter: RemoveChildResources missing."} 
	if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."} 
	if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."} 

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
	Write-Verbose "Retrieving VM: ${VirtualMachineName}"
	$VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
	$VmInfoStatus = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status
	if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
		throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
	}
    
    #Check whether VM is Managed or not
    if($VMInfo.StorageProfile.OsDisk.ManagedDisk -eq $null){
        throw "The VM : $($VMInfo.Name) does not contain managed disks."
    }

	#Gather Disk Info
	$VHDList = @()
	$VHDList += $VMInfo.StorageProfile.OsDisk.ManagedDisk.Id 
	forEach ($Vhd in ($VMInfo.StorageProfile.DataDisks.ManagedDisk.Id)) {
		$VHDList += $Vhd
	}
	Write-Verbose "Retrieved VHD List: ${VHDList}"

	# Boot Diagnostic log location
	$BootDiagnosticURI = $VmInfo.DiagnosticsProfile.BootDiagnostics.StorageUri
	$BootDiagnosticName = $BootDiagnosticURI = $VmInfoStatus.BootDiagnostics.ConsoleScreenshotBlobUri
	$BootContainerName = ""
	if (!($BootDiagnosticName -eq $null -OR $BootDiagnosticName -eq "")) {
		$BootContainerName = $VmInfoStatus.BootDiagnostics.ConsoleScreenshotBlobUri.Split('/')[-2]
		Write-Verbose "Retrieved Boot Diagnostic Log's container name: '${BootContainerName}'"
	}

	# Gather VNIC's Info
	$VnicList = $VmInfo.NetworkProfile.NetworkInterfaces.id
	Write-Verbose "Retrieved VNIC List ${VnicList}"

	# RemoveVM
	Write-Verbose "Deleting VM ${VirtualMachineName}"
	Remove-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force | Out-Null

	# Removing BootDiagnostics blob 
	Write-Verbose "Removing bootdiagnostics log blob"
	if (!($BootDiagnosticName -eq $null -OR $BootDiagnosticName -eq "")) {
		#Removing BootDiagnostics blob
		$BootStorageAcc = $BootDiagnosticURI.Split("/").split(".")[2]
		Write-Verbose "Removing BootDiagnostics blob container ${BootContainerName} from storage account ${BootStorageAcc}"
		Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -like "$BootStorageAcc"} | 
			Get-AzureStorageContainer | Where-Object {$_.name -like "$BootContainerName"} | 
			Remove-AzureStorageContainer -Force | Out-Null
	}
	
    $status = "SUCCESS"
    $resultMessage = "VM: ${VirtualMachineName} removed successfully."

	if ($RemoveChildResources -like $True) {
		Write-Verbose "Removing child resources"
        # Remove VHD
        $outputmessage = ""
	    forEach ($VHD in $VHDList) {
		    $VHDName = $VHD.Split("/")[-1]
		    Write-Verbose "Removing VHD ${VHDName} from ResourceGroup $VirtualMachineResourceGroupName"
            $result = Remove-AzureRmDisk -ResourceGroupName $VirtualMachineResourceGroupName -DiskName $VHDName -Force 
         	if($result.status -ne 'Succeeded') {
            $status = "WARNING"
            $resultMessage += "`nFailed to delete disk: ${VHDName}"
            }
	    }
		# Remove VNIC
		forEach ($Vnic in $VnicList) {
			$VnicResourceGroup = $Vnic.Split("/")[4] 
			$VnicName = $Vnic.Split("/")[-1]
			Write-Verbose "Removing VNIC ${VnicName} from resource group ${VirtualMachineResourceGroupName}"
			$VnicInfo = Get-AzureRmNetworkInterface -Name $VnicName -ResourceGroupName $VnicResourceGroup 
			Remove-AzureRmNetworkInterface -Name $VnicName -ResourceGroupName $VnicResourceGroup -Force |Out-Null
			try {
				$PublicIPAddr = ($VnicInfo.IpConfigurations.PublicIpAddress.Id).Split("/")[-1]
				Write-Verbose "Removing Public IP Resource ${PublicIPAddr}"
				Remove-AzureRmPublicIpAddress -ResourceGroupName $VnicResourceGroup -Name $PublicIPAddr -Force |Out-Null
			} catch {
				Write-Verbose "No public IP resource to remove"
			}
		}
	}

} catch {
	$status = "FAILURE"
	$resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage