#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    This script stops the specified VM

    .DESCRIPTION
    This script stops and optionally deallocates the specified VM as per the users input.

    .NOTES
    Author:      Rashmi Kanekar
    Company:     Atos
    Email:       rashmi.kanekar@atos.net
    Created:     2016-10-14
    Updated:     2017-04-06
    Version:     1.1

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
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    # Set to true to stop the OS, false to deallocate the VM
    [Parameter(Mandatory=$true)]
    [Boolean]
    $StayProvisioned,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

function Execute-StopVm {
    Param (
        # Set to true to stop the OS, false to deallocate the VM
        [Boolean]
        $StayProvisioned,

        # The name of the Resource Group that the VM is in
        [String]
        $VirtualMachineResourceGroupName,

        # The name of the VM to act upon
        [String]
        $VirtualMachineName
    )

    if ([System.Convert]::ToBoolean($StayProvisioned)) {
        Write-Verbose "Stopping VM: ${VirtualMachineName}"
        $StopVM = Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force -StayProvisioned
        Write-Verbose "Successfully stopped VM: ${VirtualMachineName}"
        return "VM: ${VirtualMachineName} in resourcegroup ${VirtualMachineResourceGroupName} stopped successfully."
    } else {
        Write-Verbose "Deallocating VM: ${VirtualMachineName}"
        $StopVM = Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Force
        Write-Verbose "Successfully deallocated VM: ${VirtualMachineName}"
        return "VM: ${VirtualMachineName} in resourcegroup ${VirtualMachineResourceGroupName} deallocated successfully."
    }
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

    $VMInfo = ""
    # Specified VM Name with Resource Group in input
    $VMInfo = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status)
    if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
        Write-Verbose "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
    }
    $VirtualMachine = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName

    foreach ($Vm in $Vminfo) {
        [string] $TempVMName = $Vm.name
        [string] $TempResourceGroup = $Vm.ResourceGroupName
        $TempVMInfo = (Get-AzureRmVM -ResourceGroupName $TempResourceGroup -Name $TempVMName -status)
        $VMStatus = ($TempVMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code

        if ($VMStatus -like "PowerState/running") {
            Write-Verbose "VM : ${TempVMName} is running"

            # Record current monitoring setting
            $MonitoringSetting = Get-AtosJsonTagValue -VirtualMachine $VirtualMachine -TagName 'atosMaintenanceString2' -KeyName 'MonStatus'
            Write-Verbose "Monitoring Setting = ${MonitoringSetting}"

            # Enable maintenance mode and update SNow if necessary
            switch ($MonitoringSetting) {
                "Monitored" {
                    # Enable Maintenance Mode and update SNow
                    Write-Verbose "Entering Maintenance Mode during VM shutdown"
                    $MonitoringResult = Disable-OMSAgent -SubscriptionId $SubscriptionId -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -Runbook $Runbook -EnableMaintenanceMode:$true
                    if ($MonitoringResult[0] -eq "SUCCESS") {
                        Write-Verbose "Successfully entered maintenance mode"
                    } else {
                        throw "Failed to enter maintenance mode: $($MonitoringResult[1])"
                    }

                    # Set MonStatus to 'Monitored' to ensure Monitoring is restarted with VM
                    Write-Verbose "Setting MonStatus to Monitored ready for restart"
                    $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'Monitored' -VirtualMachine $VirtualMachine
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
                    $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'NotMonitored' -VirtualMachine $VirtualMachine
                    break
                }
            }

            $returnMessage = Execute-StopVm -VirtualMachineResourceGroupName $TempResourceGroup -VirtualMachineName $TempVMName -StayProvisioned $StayProvisioned
            $returnMessage = "VM : ${TempVMName} in resourcegroup ${VirtualMachineResourceGroupName} stopped successfully."
        } elseif ($VMStatus -like "PowerState/deallocated") {
            Write-Verbose "VM : ${TempVMName} is in deallocated state"
            if ($StayProvisioned -eq $true) {
                $returnMessage = "VM : ${TempVMName} is in deallocated state and cannot be put in stopped state."
                throw "VM : ${TempVMName} is in deallocated state and cannot be put in stopped state."
            } else {
                $returnMessage = "VM : ${TempVMName} is already in a deallocated state - nothing to do."
            }
        } elseif($VMStatus -like "PowerState/stopped") {
            Write-Verbose "VM : ${TempVMName} is in stopped state"
            if ($StayProvisioned -eq $false) {
                $returnMessage = Execute-StopVm -VmResourceGroup $TempResourceGroup -VmName $TempVMName -StayProvisioned $StayProvisioned
            } else {
                $returnMessage = "VM : ${TempVMName} is already in a stopped state."
            }
        }
    }


    if ($ConfigurationItemId -eq 'AutomatedSchedule') {
        Write-Verbose "Runbook is running under an Azure scheduled task.  Updating SNow CMDB."
        $ManagementContext = Connect-AtosManagementSubscription
        $SnowUpdateResult = Set-SnowVmPowerStatus -SubscriptionId $SubscriptionId `
                                 -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                 -VirtualMachineName $VirtualMachineName `
                                 -Running $false
        if ($SnowUpdateResult.SubString(0,7).ToLower() -eq "success") {
            Write-Verbose "${SnowUpdateResult}"
        } else {
            throw "Failed to update SNow: ${SnowUpdateResult}"
        }
    }

    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage
