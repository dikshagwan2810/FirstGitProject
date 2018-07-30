#Requires -Modules Atos.RunbookAutomation

<#
  .SYNOPSIS
    Script to start, stop or restart multiple VMs in parallel

  .DESCRIPTION
    The script will start, stop or restart multiple VMs in parallel. The VMs are identified on the basis of the value of a tag.
    This script is intended to be executed by an automated schedule.
    The script will also enable and Disable maintenance mode on multiple monitored Vms.

  .INPUTS
   $SubscriptionID = THe subscription ID of the subscription, of which all the VMs will be part of.
   $TagName = Name of the Tag which will be used to identify the VMs.
   $VirtualMachineAction = Action to be performed, either to start, stop, or restart the VMs specified.

  .OUTPUTS
    Displays processes step by step during execution

  .NOTES
    Author:      Austin Palakunnel,Ankita Chaudhari, Rashmi Kanekar
    Company:     Atos
    Email:       austin.palakunnel@atos.net,ankita.chaudhari@atos.net,rashmi.kanekar@atos.net
    Created:     03 Jan 2017
    Version:     1.0

   .Note
        Enable the Log verbose records of runbook

#>
param(
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Start-VM","Stop-VM","Restart-VM","Enable-MaintenanceMode","Disable-MaintenanceMode")]
    [string]
    $VirtualMachineAction,

    [Parameter(Mandatory=$true)]
    [string]
    $TagName
)

try
{
    # Validate parameters (PowerShell parameter validation is not available in Azure)
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId empty."}
    if ([string]::IsNullOrEmpty($TagName)) {throw "Input parameter Tagname missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineAction)) {throw "Input parameter: Action empty."}
    $allowedActions = "Start-VM","Stop-VM","Restart-VM","Enable-MaintenanceMode","Disable-MaintenanceMode"
    if (!($allowedActions -Contains $VirtualMachineAction)) {
        throw "VirtualMachineAction must be one of $($allowedActions -join ', ')"
    }

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

    Write-Verbose "Specified VM Names ${VmNames} with Subscription ID ${SubscriptionId} in input"

    $ListOfVMs = Get-AzureRmVM -WarningAction SilentlyContinue
    if($ListOfVMs -eq $null) {
        throw "VMs in Subscription ID ${SubscriptionId} not found"
    }

    #Finding all VMs with Tag Name specified
    $KeyName = "atosMaintenanceString1"
    $ScheduleVMs = @()
    foreach ($VM in $ListOfVMs) {
        if ($VM.Tags["$KeyName"] -match "^([a-zA-Z_\s$-?]+,)*\s*$TagName\s*(,[a-zA-Z_\s$-?]+)*$") {
            $ScheduleVMs+= $VM
        }
    }
    if ($ScheduleVMs -eq $null) {
        throw "No VMs have been found on which scheduled action is to be performed"
    }



    if($VirtualMachineAction -like "Start-VM" -or $VirtualMachineAction -like "Stop-VM" -or $VirtualMachineAction -like "Restart-VM")
    {
        # # Connect to the management subscription
        Write-Verbose "Connect to default subscription"
        $ManagementContext = Connect-AtosManagementSubscription
        # Scheduled VMs need to be started, stopped or restarted as per $VirtualMachineAction
        forEach ($VM in $ScheduleVMs) {
            $VMParameters = @{
                SubscriptionId = $SubscriptionId
                VirtualMachineName = "$($VM.Name)"
                VirtualMachineResourceGroupName = "$($VM.ResourceGroupName)"
                RequestorUserAccount = "AutomatedSchedule-${TagName}"
                ConfigurationItemId = "AutomatedSchedule"
            }
            if ($VirtualMachineAction -like "Stop-VM") {
                #$VMParameters.Add("StayProvisioned","false")
                                            $VMParameters = @{
                SubscriptionId = $SubscriptionId
                VirtualMachineName = "$($VM.Name)"
                VirtualMachineResourceGroupName = "$($VM.ResourceGroupName)"
                RequestorUserAccount = "AutomatedSchedule-${TagName}"
                ConfigurationItemId = "AutomatedSchedule"
                StayProvisioned = $false
            }
            }
            Write-Verbose "Starting runbook ${VirtualMachineAction} with the following parameters:"
            $VMParameters.GetEnumerator() | ForEach-Object {
                Write-Verbose " -> $($_.Key) = $($_.Value)"
            }

            # This will start a runbook but will not wait for output
            $ChildRunbook = Start-AzureRmAutomationRunbook -Name $VirtualMachineAction -Parameters $VMParameters -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount

            $returnMessage = "Action ${VirtualMachineAction} started"
        }
    }
    elseif($VirtualMachineAction -like "Enable-MaintenanceMode")
    {
        # Switch to customer's subscription context
        Write-Verbose "Connect to customer subscription"
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections
        $SuccessfulVmList = @()
        $FailedVmList = @()

        # Scheduled VMs need to be enable in maintenance mode
        forEach ($VM in $ScheduleVMs)
        {
            Write-Verbose "Enabling maintenance mode on $($VM.Name)"
            $MonitoringTagValue = Get-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus"
            Write-Verbose "Current MonStatus: ${MonitoringTagValue}"
            $VirtualMachineResourceGroupName = $VM.ResourceGroupName
            $VirtualMachineName = $VM.Name
            if ($MonitoringTagValue -eq "Monitored")
            {
                #Disable OMS Agent
                $OMSResult = Disable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook -EnableMaintenanceMode $true
                Write-Verbose "$($OMSResult[2])"
                if ($OMSResult[0] -eq "FAILURE")
                {
                    $FailedVmList += $Vm.Name
                }
                elseif($OMSResult[0] -eq "SUCCESS")
                {
                    $SuccessfulVmList += $Vm.Name
                }
            }
            elseif ($MonitoringTagValue -eq "MaintenanceMode")
            {
                Write-Verbose "VM $($VM.Name) is already in maintenance mode"
                $SuccessfulVmList += $Vm.Name
            }
            else
            {
                Write-Verbose "VM $($VM.Name) is not monitored and therefore cannot enter maintenance mode"
                $FailedVmList += $Vm.Name
            }
        }

        $ManagementContext = Connect-AtosManagementSubscription
        forEach ($VM in $ScheduleVMs) {
            if ($SuccessfulVmList -contains $VM.Name) {
                Write-Verbose "Setting $($VM.Name) status to MaintenanceMode in SNow"
                $SnowUpdateResult = Set-SnowVmMonitoringStatus -SubscriptionId $SubscriptionId `
                                 -VirtualMachineResourceGroupName $VM.ResourceGroupName `
                                 -VirtualMachineName $VM.Name `
                                 -MonitoringStatus 'MaintenanceMode'
                if ($SnowUpdateResult.SubString(0,7).ToLower() -eq "success") {
                    Write-Verbose "${SnowUpdateResult}"
                } else {
                    Write-Verbose "Error - Failed to update SNow: ${SnowUpdateResult}"
                }
            }
        }

        $returnMessage = "Successfully enabled maintenance mode on VMs: $($SuccessfulVmList -join "," )`nFailed to enable maintenance mode on VMs: $($FailedVmList -join "," )"
    }
    elseif($VirtualMachineAction -like "Disable-MaintenanceMode")
    {
        # Switch to customer's subscription context
        Write-Verbose "Connect to customer subscription"
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections
        $SuccessfulVmList = @()
        $FailedVmList = @()
        # Scheduled VMs need to be disable from maintenance mode
        forEach ($VM in $ScheduleVMs)
        {
            Write-Verbose "Disabling maintenance mode on $($VM.Name)"
            $MonitoringTagValue = Get-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus"
            Write-Verbose "Current MonStatus: ${MonitoringTagValue}"
            $VirtualMachineResourceGroupName = $VM.ResourceGroupName
            $VirtualMachineName = $VM.Name
            if ($MonitoringTagValue -eq "MaintenanceMode")
            {
                #Enabling OMS Agent for any state of VM
                $OMSResult = Enable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook
                Write-Verbose "$($OMSResult[2])"
                if ($OMSResult[0] -eq "FAILURE")
                {
                    $FailedVmList += $Vm.Name
                }
                elseif($OMSResult[0] -eq "SUCCESS")
                {
                    $SuccessfulVmList += $Vm.Name
                }
            }
            elseif ($MonitoringTagValue -eq "Monitored")
            {
                Write-Verbose "VM $($VM.Name) has already exited maintenance mode"
                $SuccessfulVmList += $Vm.Name
            }
            else
            {
                Write-Verbose "VM $($VM.Name) is not in maintenance mode and therefore cannot exit maintenance mode"
                $FailedVmList += $Vm.Name
            }
        }

        $ManagementContext = Connect-AtosManagementSubscription
        forEach ($VM in $ScheduleVMs) {
            if ($SuccessfulVmList -contains $VM.Name) {
                Write-Verbose "Setting $($VM.Name) status to Monitored in SNow"
                $SNowUpdateResult = Set-SnowVmMonitoringStatus -SubscriptionId $SubscriptionId `
                                 -VirtualMachineResourceGroupName $VM.ResourceGroupName `
                                 -VirtualMachineName $VM.Name `
                                 -MonitoringStatus 'Monitored'
                if ($SnowUpdateResult.SubString(0,7).ToLower() -eq "success") {
                    Write-Verbose "${SnowUpdateResult}"
                } else {
                    Write-Verbose "Error - Failed to update SNow: ${SnowUpdateResult}"
                }
            }
        }
        $returnMessage = "Successfully disabled maintenance mode on VMs: $($SuccessfulVmList -join "," )`nFailed to disable maintenance mode on VMs: $($FailedVmList -join "," )"
    }

    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage
