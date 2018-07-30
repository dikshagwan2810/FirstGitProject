#Requires -Modules Atos.RunbookAutomation
<#
  .SYNOPSIS
    Script to remove/ delete an existing automated schedule for the Invoke-VmAction.
  
  .DESCRIPTION
    Script to remove/ delete an automated schedule for the Invoke-VmAction runbook based on the input ScheduleName.
  
  .NOTES
    Author:     Austin Palakunnel
    Company:    Atos
    Email:      austin.palakunnel@atos.net
    Created:    2017-01-05
    Updated:    2017-04-10
    Version:    1.0
   
   .Note 
        Enable the Log verbose records of runbook 

#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)] 
    [String] 
    $SubscriptionId,

    # The name of the schedule to remove
    [Parameter(Mandatory=$true)] 
    [String] 
    $ScheduleName,

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
    $KeyName = "atosMaintenanceString1"

    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId empty."}
    if ([string]::IsNullOrEmpty($ScheduleName)) {throw "Input parameter: ScheduleName empty."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount empty."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId empty."}

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    $ScheduleToBeDeleted = Get-AzureRmAutomationSchedule -Name $ScheduleName -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount
    if ($ScheduleToBeDeleted -eq $null -or $ScheduleToBeDeleted -eq "") {
        throw "Schedule to be deleted: '${ScheduleName}' not found."
    }

    $TagName = $ScheduleToBeDeleted.Description
    if ([string]::IsNullOrEmpty($TagName)) {
        throw "Tag name is null or empty!"
    }

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    Write-Verbose "Fetching all VMs with Tag name '${TagName}'"
    # Code to fetch all VMs based on particular TagName
    $ListOfVMs = @()
    $ListOfVMs = Get-AzureRmVM
    $ScheduleVMs = @()
    foreach ($VM in $ListOfVMs) {
        if ($VM.Tags["$KeyName"] -match "^([a-zA-Z_\s$-?]+,)*\s*$TagName\s*(,[a-zA-Z_\s$-?]+)*$") {
            $ScheduleVMs += $VM
        }
    }
    Write-Verbose "Removing tags from VMs."
    # Remove tag from all these VMs
    foreach ($VM in $ScheduleVMs) {
        Write-Verbose "Updating VM $($VM.Name)"
        # Code for removing tag
        $Tags = $VM.Tags
        $TagValue = $VM.Tags["$KeyName"]
        if ($TagValue -like "$TagName") {
            Write-Verbose "  Removing tag ${KeyName}"
            $Tags.Remove("$KeyName") | Out-Null
        } else {
            $TagValue = $TagValue.Replace("$TagName,","").Replace(",$TagName","")
            Write-Verbose "  Setting Tag ${KeyName} Value tp ${TagValue}"
            $Tags["$KeyName"]="$TagValue"
        }
        # Set tags to VM
        $SetTagOperation = Set-AzureRmResource -ResourceId $VM.Id -Tag $Tags -Force
        Write-Verbose $SetTagOperation
    }

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Removing schedule '${ScheduleName}'"
    $RemoveScheduleOperation = Remove-AzureRmAutomationSchedule -Name $ScheduleName -Force -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount

    $status = "SUCCESS"
    $resultMessage = "Removed schedule '${ScheduleName}'"
} catch {
    $ErrorState = 2
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
