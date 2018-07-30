#Requires -Modules Atos.RunbookAutomation

<#
  .SYNOPSIS
    Script to Start VM.

  .DESCRIPTION
    Script to start VM
    The script will check whether the VM is in deallocated or stopped state if yes then it will start the VM.

  .OUTPUTS
    Displays processes step by step during execution

  .NOTES
    Author:     Ankita Chaudhari, Russell Pitcher
    Company:    Atos
    Email:      ankita.chaudhari@atos.net
    Created:    2017-11-14
    Updated:    2017-04-07
    Version:    1.1
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

    $VMInfo = ""
    if ($VirtualMachineName -ne $null -and $VirtualMachineResourceGroupName -ne $null) {
        # Specified VM Name with Resource Group in input
        Write-Verbose "Specified VM Name with Resource Group in input"
        $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        }
    } elseif ($VirtualMachineResourceGroupName -ne $null -and $VirtualMachineName -eq $null) {
        # Only Resource Group is provided in input
        Write-Verbose "Specified Resource Group in input"
        $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "Resource Group ${VirtualMachineResourceGroupName} not found"
        }
    }

    foreach ($VMs in $VMInfo) {
        $TempVMName = $VMs.name
        Write-Verbose "VMName is ${TempVMName}"

        $ResourceGroupName = $VMs.ResourceGroupName
        Write-Verbose "ResourceGroupName is ${ResourceGroupName}"

        $TempVMInfo = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $TempVMName -status
        $VMStatus = ($TempVMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code
        Write-Verbose "Status of VM is ${VMStatus}"

        if ($VMStatus -like "PowerState/Running") {
            Write-Verbose "Machine is in running state"
            $returnMessage = "VM: ${TempVmName} is already running."
            $status = "SUCCESS"
        } elseif ($VMStatus -like "PowerState/deallocated") {
            Write-Verbose "Starting machine ${TempVMName}..."
            $StartVM = Start-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $TempVMName
            Write-Verbose "Successfully Started the machine ${TempVMName}"
            $returnMessage = "VM: ${TempVMName} started successfully."
            $status = "SUCCESS"
        } elseif ($VMStatus -like "PowerState/stopped") {
            Write-Verbose "Starting machine ${TempVMName}..."
            $StartVM = Start-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $TempVMName
            Write-Verbose "Successfully Started the machine ${TempVMName}"
            $returnMessage = "VM: ${TempVMName} started successfully."
            $status = "SUCCESS"
        } else {
            Write-Error "Unexpected Machine State of the machine ${TempVMName}"
            $status = "FAILURE"
        }

        #Enabling Monitoring if the Monitoring Tag value is set to "Monitored"
        # Record current monitoring setting
        $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VMs -TagName atosMaintenanceString2 -KeyName MonStatus

        # Disable Maintenance Mode and update SNow if necessary
        switch ($MonitoringSetting) {
            "Monitored"{
                Write-Verbose "Exiting maintenance mode and re-enabling monitoring"
                $MonitoringResult = Enable-OMSAgent -SubscriptionId $SubscriptionId -VirtualMachineResourceGroupName $ResourceGroupName -VirtualMachineName $TempVMName -Runbook $Runbook
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
                $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $VMs
                break
            }
        }

        if (($status -eq "SUCCESS") -and ($ConfigurationItemId -eq 'AutomatedSchedule')) {
            Write-Verbose "Runbook is running under an Azure scheduled task.  Updating SNow CMDB."
            $ManagementContext = Connect-AtosManagementSubscription
            $SnowUpdateResult = Set-SnowVmPowerStatus -SubscriptionId $SubscriptionId `
                                     -VirtualMachineResourceGroupName $ResourceGroupName `
                                     -VirtualMachineName $TempVMName `
                                     -Running $true
            if ($SnowUpdateResult.SubString(0,7).ToLower() -eq "success") {
                Write-Verbose "${SnowUpdateResult}"
            } else {
                throw "Failed to update SNow: ${SnowUpdateResult}"
            }
        }
    }
} catch {
	$status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage