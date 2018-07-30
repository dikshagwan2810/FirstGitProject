#Requires -Modules Atos.RunbookAutomation

<#
    .SYNOPSIS
    This script enables or disables management agents

    .DESCRIPTION
    This script will enable management of the specified VM, setting the values of a number of Azure tags.
    It will also optionally enable or disable the monitoring agent and enable or disable scheduled Azure Reocvery Services IaaS VM Backups

    .NOTES
    Author:     Arun Sabale, Russell Pitcher,Ankita Chaudhari, Rashmi Kanekar
    Company:    Atos
    Email:      Arun.sabale@atos.net, russell.pitcher@atos.net,ankita.chaudhari@atos.net,rashmi.kanekar@atos.net
    Created:    2017-01-05
    Updated:    2017-06-23
    Version:    3.0
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String] [ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String] [ValidateNotNullOrEmpty()]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String] [ValidateNotNullOrEmpty()]
    $VirtualMachineResourceGroupName,

    # Set true to enable the monitoring agent
    [Parameter(Mandatory=$true)]
    [Boolean]
    $EnableMonitoring,

    # Set true to enable EnableMaintenanceMode
    [Parameter(Mandatory=$true)]
    [Boolean]
    $EnableMaintenanceMode,

    # Set true to enable scheduled IaaS VM Backup
    [Parameter(Mandatory=$true)]
    [Boolean]
    $EnableBackup,

    # The value for the costCenter tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String]
    $costCenter,

    # The value for the projectName tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String]
    $projectName,

    # The value for the appName tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String]
    $appName,

    # The value for the supportGroup tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String]
    $supportGroup,

    # The value for the environment tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String]
    $environment,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String] [ValidateNotNullOrEmpty()]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String] [ValidateNotNullOrEmpty()]
    $ConfigurationItemId
)

try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    Write-Verbose "Check for Resource Group and VM"
    $ResourceGroup = Get-AzureRmResourceGroup -name $VirtualMachineResourceGroupName
    if (!$?) {throw "Resource group '${VirtualMachineResourceGroupName}' could not be found"}
    $VirtualMachine = Get-AzureRmVm -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
    if (!$?) {throw "Virtual Machine '${VirtualMachineName}' could not be found in resource group '${VirtualMachineResourceGroupName}'"}

    # Enable or Disable backup
    try {
        if ($EnableBackup -eq $true) {
            Write-Verbose "Enabling Iaas VM Backup"
            $BackupResult = Enable-AtosIaasVmBackup -SubscriptionId $SubscriptionId -VirtualMachineName $VirtualMachineName -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName
        } else {
            Write-Verbose "Disabling Iaas VM Backup (leaving any existing recovery points intact)"
            $BackupResult = Disable-AtosIaasVmBackup -SubscriptionId $SubscriptionId -VirtualMachineName $VirtualMachineName -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -RemoveRecoveryPoints $true
        }
    } catch {
        $BackupResult = @()
        $BackupResult += "FAILURE"
        $BackupResult += $_.ToString()
    }
    Write-Verbose "Backup Result:"
    $BackupResult | ForEach-Object {Write-Verbose "  $($_.ToString())"}


    # Set tag values for VM and associated NICs
    try {
        if ("${costCenter}${projectName}${appName}${supportGroup}${environment}" -eq '') {
            $TAGresult = @()
            $TAGresult += "SUCCESS"
            $TAGresult += "No changes for Tags"
        } else {
            $TagResult = Set-AtosVmTags -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName `
                                        -VirtualMachineName $VirtualMachineName `
                                        -costCenter $costCenter `
                                        -projectName $projectName `
                                        -appName $appName `
                                        -supportGroup $supportGroup `
                                        -environment $environment `
                                        -ConfigurationItem $ConfigurationItemId
        }
    } catch {
        $TAGresult = @()
        $TAGresult += "FAILURE"
        $TAGresult += $_.ToString()
    }
    Write-Verbose "TAG Result:"
    $TAGresult | ForEach-Object {Write-Verbose "  $($_.ToString())"}


    # Enable or Disable monitoring
    try {
        $VM = Get-AzureRmVM -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
        if (!$VM) {
            throw "Cannot find VM ${VirtualMachineName} in resource group ${VirtualMachineResourceGroupName}"
        }
        $VMStatus = (Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status | Select-Object -ExpandProperty Statuses)[1].code
        $MonitoringTagValue = Get-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus"
        if ($EnableMonitoring -eq $true) {
            if($EnableMaintenanceMode -eq $true)
            {
                if($MonitoringTagValue -eq "NotMonitored" -or $MonitoringTagValue -eq "Monitored")
                {
                    #Disable OMS Agent
                    $OMSResult = Disable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook -EnableMaintenanceMode $true
                    Write-Verbose "$($OMSResult[2])"
                    if ($OMSResult[0] -eq "FAILURE")
                    {
                        throw "$($OMSResult[1])"
                    }
                }
                elseif($MonitoringTagValue -eq $null -or $MonitoringTagValue -eq "")
                {
                    $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue "MaintenanceMode"
                    $OMSResult = @("SUCCESS","VM: ${VirtualMachineName} is under maintenance mode")
                    Write-Verbose "VM: ${VirtualMachineName} is under maintenance mode"
                }
                elseif($MonitoringTagValue -eq "MaintenanceMode")
                {
                    $OMSResult = @("SUCCESS","VM: ${VirtualMachineName} is under maintenance mode")
                    Write-Verbose "VM: ${VirtualMachineName} is already in MaintenanceMode"
                }
                else
                {
                    throw "Unexpected Tag value ${MonitoringTagValue} for key MonStatus"
                }
            }
            elseif($EnableMaintenanceMode -eq $false)
            {
                if($MonitoringTagValue -eq $null -or $MonitoringTagValue -eq "")
                {
                    if ($VMStatus -like "PowerState/deallocated" -or $VMStatus -like "PowerState/stopped")
                    {
                        $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue "Monitored"
                        $OMSResult = @("SUCCESS","VM: ${VirtualMachineName} added in monitoring")
                        Write-Verbose "VM: ${VirtualMachineName} added in monitoring"
                    }
                    else
                    {
                        #Enabling OMS Agent for any state of VM
                        $OMSResult = Enable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook
                        Write-Verbose "$($OMSResult[2])"
                        if ($OMSResult[0] -eq "FAILURE")
                        {
                            throw "$($OMSResult[1])"
                        }

                    }
                }
                else
                {
                    #Enabling OMS Agent for any state of VM
                    $OMSResult = Enable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook
                    Write-Verbose "$($OMSResult[2])"
                    if ($OMSResult[0] -eq "FAILURE")
                    {
                        throw "$($OMSResult[1])"
                    }
                }

            }

        }
        elseif($EnableMonitoring -eq $false)
        {
            if($EnableMaintenanceMode -eq $true)
            {
                if($MonitoringTagValue -eq $null -or $MonitoringTagValue -eq "")
                {
                    $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue "NotMonitored"
                }
                throw "Please enable Monitoring first on VM ${VirtualMachineName} to enable Maintenance Mode on the Machine."
            }
            elseif($EnableMaintenanceMode -eq $false)
            {
                if($MonitoringTagValue -eq "Monitored" -or $MonitoringTagValue -eq "MaintenanceMode")
                {
                    #Disable OMS Agent as enable monitoring is set to FALSE
                    $OMSResult = Disable-OMSAgent -VirtualMachineResourceGroupName $VirtualMachineResourceGroupName -VirtualMachineName $VirtualMachineName -SubscriptionId $SubscriptionId -Runbook $Runbook -EnableMaintenanceMode $false
                    Write-Verbose "$($OMSResult[0])"
                    if ($OMSResult[0] -eq "FAILURE")
                    {
                        throw "$($OMSResult[1])"
                    }
                }
                elseif($MonitoringTagValue -eq $null -or $MonitoringTagValue -eq "")
                {
                    $SetTagValue = Set-AtosJsonTagValue -VirtualMachine $VM -TagName "atosMaintenanceString2" -KeyName "MonStatus" -KeyValue "NotMonitored"
                    $OMSResult = @("SUCCESS","VM: ${VirtualMachineName} removed from monitoring")
                    Write-Verbose "VM: ${VirtualMachineName} removed from monitoring"
                }
                elseif($MonitoringTagValue -eq "NotMonitored")
                {
                    $OMSResult = @("SUCCESS","VM: ${VirtualMachineName} removed from monitoring")
                    Write-Verbose "VM: ${VirtualMachineName} is already NotMonitored"
                }
                else
                {
                    throw "Unexpected Tag value $MonitoringTagValue for key MonStatus"
                }
            }
        }
    } catch {
        $OMSResult = @()
        $OMSResult += "FAILURE"
        $OMSResult += $_.ToString()
    }
    Write-Verbose "OMS Result:"
    $OMSResult | ForEach-Object {Write-Verbose "  $($_.ToString())"}


    # Collate overall results and output
    try {
        if (($OMSResult[0] -eq "SUCCESS") -and ($TAGresult[0] -eq "SUCCESS") -and ($BackupResult[0] -eq "SUCCESS")) {
            $status = "SUCCESS"
        } else {
            $status = "FAILURE"
        }
    } catch {
        $status = "FAILURE"
    }

    $resultMessage = "Monitoring: $($OMSResult -join ' : ') "
    $resultMessage += "Tags: $($TAGresult -join ' : ') "
    $resultMessage += "Backup: $($BackupResult -join ' : ')"

} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
