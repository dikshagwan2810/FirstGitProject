#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    Script to change the T-Shirt Size of the VM.

    .DESCRIPTION
    Script to change the T-Shirt Size of the VM.
    The script will change the T-Shirt size of the VM as mentioned by the user.
    The script only handles the changes to following
    Standard to Premium, Standard to Standard and Premium to Premium.

    .NOTES
    Author:   Ankita Chaudhari
    Company:  Atos
    Email:    ankita.chaudhari@atos.net
    Created:  2016-11-30
    Updated:  2017-04-19
    Version:  1.1

    .Note 
    Enable the Log verbose records of runbook 
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

    # The new Azure size for the VM
    [Parameter(Mandatory=$true)] 
    [String] [ValidateNotNullOrEmpty()]
    $VirtualMachineSize,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

function Max-DataDiskCount {
    param (
        $ResourceGroup,
        $VirtualMachineName,
        $NewVirtualMachineSize
    )

    $VMInfo = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VirtualMachineName
    $CurrentMaxDataDiskCount = $VmInfo.StorageProfile.DataDisks.Count
    $NewMaxDataDiskCount = Get-AzureRmVMSize -ResourceGroupName $ResourceGroup -VMname $VirtualMachineName |
                            Where-Object {$_.Name -like $NewVirtualMachineSize} | 
                            Select-Object -ExpandProperty MaxDataDiskCount
    if ($CurrentMaxDataDiskCount -gt $NewMaxDataDiskCount) {
        $Result = $false
    } else {
        $Result = $true
    }
    return $Result
}

function Change-HardwareProfile {
    param (
        $ResourceGroup,
        $VirtualMachineName,
        $NewVirtualMachineSize
    )

    $VMInfo = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VirtualMachineName
    $VMInfo.HardwareProfile.vmSize = $NewVirtualMachineSize
    Write-Verbose "Updating the Profile"
    $UpdateVM = Update-AzureRmVM -ResourceGroupName $ResourceGroup -VM $VMInfo
    if ($UpdateVM.StatusCode -eq "OK") {
        Write-Verbose "Updated the Profile"
        $returnMessage = "VM: ${VirtualMachineName} resized successfully to new size: ${NewVirtualMachineSize}"
    } else {
        throw "Failed to update T-shirt size of VM ${VirtualMachineName}"
    }
    return $returnMessage
}

try {
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."} 
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter: VirtualMachineName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineSize)) {throw "Input parameter: VirtualMachineSize missing."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}

    $NewVirtualMachineSize = $VirtualMachineSize.Replace(" ", "_")


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

    $ErrorState = 0
    [string] $returnMessage = ""
    $VMInfo = ""

    if ($VirtualMachineName -ne $null) {
        $VMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName)
        #$VirtualMachineResourceGroupName = $VMInfo.resourcegroup
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        } else {
            Write-Verbose "VM found can proceed to change the size"
        }
    } 

    $CurrentProfile = $VMInfo.HardwareProfile.VmSize
    $CurrentSize = $CurrentProfile.Split("_")[1]
    $NewSize = $NewVirtualMachineSize.Split("_")[1]

    #Checking the machine state
    $TempVMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status)
    $VMStatus = ($TempVMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code
    Write-Verbose "Status of VM is ${VMStatus}"
    if ($VMStatus -like "PowerState/Running") {
        throw "VM: ${VirtualMachineName} is in running state. Please stop (deallocate) the VM."
    }
    #End of checking the machine state

    #Validating the old and new profile
    if ($CurrentProfile -eq $NewVirtualMachineSize) {
        throw "VM ${VirtualMachineName} has ${CurrentProfile} select another profile"
    }
    #End of validating profile

    #Perform the check for the Account Type and Data Disk Count
    #Checking the new hardware profile account type
    if ($NewSize -match "s") {
        $NewHWSizeType = "Premium"
    } else {
        $NewHWSizeType = "Standard"
    }
    #End of checking new hardware profile account type

    #Checking the Current profiles account type
    if ($CurrentSize -match "s") {
        $CurrentHWSizeType = "Premium"
    } else {
        $CurrentHWSizeType = "Standard"
    }
    #End of Checking the Current profiles account type

    #Changing the T-Shirt Size of the VM
    if ($CurrentHWSizeType -eq "Premium") {
        Write-Verbose "Current Storage tier is Premium"
        if ($NewHWSizeType -eq "Standard") {
            throw "Changing T-Shirt Size from Premium to Standard is not possible"
        } else {
            $DataCount = Max-DataDiskCount -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            if ($DataCount -eq $true) {
                #Convert the T-Shirt Size to new size
                $returnMessage = Change-HardwareProfile -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            } else {
                throw "This Hardware Profile is not supported."
            }
        }
    } elseif ($CurrentHWSizeType -eq "Standard") {
        Write-Verbose "Current Storage tier is Standard"
        if ($NewHWSizeType -eq "Standard") {
            $DataCount = Max-DataDiskCount -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            if ($DataCount -eq $true) {
                #Convert the T-Shirt Size to new size
                $returnMessage = Change-HardwareProfile -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            } else {
                throw "This Hardware Profile is not supported"
            }
        } else {
            $DataCount = Max-DataDiskCount -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            if ($DataCount -eq $true) {
                #Convert the T-Shirt Size to new size
                $returnMessage = Change-HardwareProfile -ResourceGroup $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -NewVirtualMachineSize $NewVirtualMachineSize
            } else {
                throw "This Hardware Profile is not supported"
            }
        }
    }
    #End of Changing the T-Shirt Size of the VM
    #End of Account Type check and Data Disk Count

    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
    Write-Error $returnMessage
}

Write-Output $status
Write-Output $returnMessage
