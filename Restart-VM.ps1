#Requires -Modules Atos.RunbookAutomation
<#
  .SYNOPSIS
    Script to Restart VM.
 
  .DESCRIPTION
    Script to Restart VM
    The script will check whether the VM is in running state if yes then it will Restart the VM.
 
  .OUTPUTS
    Displays processes step by step during execution
 
  .NOTES
    Author:     Ankita Chaudhari
    Company:    Atos
    Email:      ankita.chaudhari@atos.net
    Created:    2016-11-21
    Updated:    2017-04-07
    Version:    1.0
  
   .Note
        Enable the Log verbose records of runbook
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
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter: VirtualMachineName missing."}
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

    $returnMessage = ""
    $VMInfo = ""
    if ($VirtualMachineName -ne $null) {
        $VMInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -status
        #$ResourceGroup = $VMInfo.resourcegroup
        if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
            throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
        } else {
            Write-Verbose "VM found can proceed to reboot"
        }
    }

    $VMStatus = ($VMInfo.Statuses | Where-Object {$_.code -like "PowerState/*"}).code  
    Write-Verbose "VM Status is $VMStatus"

    if ($VMStatus -like "PowerState/running") {
        Write-Verbose "Rebooting Vm : ${VirtualMachineName}"
        $RestartVM = Restart-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        Write-Verbose "Successfully Rebooted VM ${VirtualMachineName}"
        $returnMessage = "VM: ${VirtualMachineName} was successfully re-started."
        $status = "SUCCESS"
    } 
    elseif ($VMStatus -like "PowerState/deallocated") 
    {
        throw "VM: ${VirtualMachineName} is in a deallocated state. Please use Start-VM to start a stopped VM."
    } 
    elseif ($VMStatus -like "PowerState/stopped") 
    {
        throw "VM: ${VirtualMachineName} is in a stopped state. Please use Start-VM to start a stopped VM."
    } 
    else 
    {
        throw "VM: ${VirtualMachineName} is in an unknown state (${VMStatus}) and cannot be restarted."
    }
} catch {
    $status = "FAILURE"
    $returnMessage = "$_"
}
        
Write-Output $status
Write-Output $returnMessage 
