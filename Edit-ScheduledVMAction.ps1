<#
  .SYNOPSIS
    Script to edit an existing automated schedule for the Invoke-VmAction.
  
  .DESCRIPTION
    Script to edit an already automated schedule for the Invoke-VmAction runbook.
    It will accept the required new parameters and provide to the runbook as well.
  
  .OUTPUTS
    Displays processes step by step during execution
  
  .NOTES
    Author:     Austin Palakunnel,Rashmi Kanekar               
    Company:    Atos
    Email:      austin.palakunnel@atos.net, rashmi.kanekar@atos.net
    Created:    2017-01-05
    Updated:    2017-05-09
    Version:    1.2
   
   .Note 
    1.0 Enable the Log verbose records of runbook 
    1.1 Use module and harmonise parameters
    1.2 Improve WeekDays validation
#>

param(
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The names of the VMs to act upon
    [Parameter(Mandatory=$false)]
    [String] 
    $VirtualMachineNames,

    # The name if the schedule to edit
    [Parameter(Mandatory=$true)]
    [String] 
    $ScheduleName,

    # The new name for the updated schedule
    [Parameter(Mandatory=$false)]
    [String] 
    $NewScheduleName,

    # The start time and date for the schedule
    [Parameter(Mandatory=$true)]
    [String] 
    $ScheduleStart,

    # The time zone to use
    [Parameter(Mandatory=$true)]
    [String] 
    $TimeZone,

    # The weekdays that the schedule should run on 
    [Parameter(Mandatory=$true)]
    [String] 
    $WeekDays,

    # The time and date for the schedule to expire
    [Parameter(Mandatory=$false)]
    [String] 
    $ScheduleExpiration,

    # The action for the schedule to performe
    [Parameter(Mandatory=$true)]
    [String]
    $ScheduleAction,

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
    $returnMessage = ""

    ###Validation section
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId empty."} 
    if ([string]::IsNullOrEmpty($VirtualMachineNames)) {throw "Input parameter: VirtualMachineNames empty."}
    if ([string]::IsNullOrEmpty($ScheduleName)) {throw "Input parameter: ScheduleName empty."}        
    if ([string]::IsNullOrEmpty($ScheduleStart)) {throw "Input parameter: ScheduleStart empty."}
    if ([string]::IsNullOrEmpty($TimeZone)) {throw "Input parameter: TimeZone empty."}
    if ([string]::IsNullOrEmpty($WeekDays)) {throw "Input parameter: WeekDays empty."}
    if ([string]::IsNullOrEmpty($ScheduleAction)) {throw "Input parameter: ScheduleAction empty."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount empty."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId empty."}
    
    $allowedDays = 'monday','tuesday','wednesday','thursday','friday','saturday','sunday'
    $WeekDaysArray = $WeekDays.Split(',')
    forEach ($day in $WeekDaysArray) {
        if ($allowedDays -notContains $day) {
           throw "Invalid input for WeekDays : '${WeekDays}'"
        }
    }

    $ScheduleAction = $ScheduleAction.Trim()
    if ($ScheduleAction -notlike "Start-VM" -and $ScheduleAction -notlike "Stop-VM" -and $ScheduleAction -notlike "Restart-VM"  -and $ScheduleAction -notlike "Enable-MaintenanceMode" -and $ScheduleAction -notlike "Disable-MaintenanceMode") {
        throw "Invalid input for ScheduleAction : $ScheduleAction"
    }
    
    try {
        $StartDateTime = [datetime]::ParseExact("$ScheduleStart","yyyy-M-d H:m:s",$null)
    } catch {
        throw "Invalid input for ScheduleStart : ${ScheduleStart}"
    }

    if ($StartDateTime -le $([datetime]::Now.AddHours(1))) {
        throw "Invalid input for ScheduleStart : ${ScheduleStart}. Specify a datetime atleast 1 hour past the current datetime"
    }
    
    if ($ScheduleExpiration -ne $null -and $ScheduleExpiration -notlike "") {
        $UseExpireDate = $true
        try {
            $ExpirationDate = [datetime]::ParseExact("$ScheduleExpiration","yyyy-M-d H:m:s",$null)
        } catch {
            throw "Invalid input for ScheduleExpiration : ${ScheduleExpiration}"
        }
        if ($ExpirationDate -le $([datetime]::Now.AddHours(1))) {
            throw "Invalid input for ScheduleExpiration : ${ScheduleExpiration}. Specify a datetime atleast 1 hour past the current datetime"
        }
    }

    $TimeZoneCheck = [timezoneinfo]::GetSystemTimeZones() | Where-Object {$_.id -eq $TimeZone}
    if ($TimeZoneCheck -eq $null) {
        throw "Invalid input for TimeZone : ${TimeZone}"
    }
    ##End of validation section
    

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    
    Write-Verbose "Checking if new schedule with same name already exists"
    try {
        if ($NewScheduleName -notlike "" -and $NewScheduleName -ne $null) {
            #Validation of Schedule Name
            if ($NewScheduleName -match "^[a-zA-Z0-9 ]*$") {
		        Write-Verbose "Correct Resource Group name"
	        } else {
                throw "Schedule Name $NewScheduleName specified contains special characters. Only aplhanumeric characters are allowed for schedule name"
            }
            $ScheduleCheck = Get-AzureRmAutomationSchedule -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount | Where-Object {$_.Name -like "$NewScheduleName"}
        }
    } catch {
        ###Nothing to do.. Error expected if no schedule found
        #Write-Verbose $_.Exception.GetType().FullName
    }
    if($ScheduleCheck -ne $null) {
        throw "Schedule with name $NewScheduleName already exists. Please provide a unique name for new schedule."
    }
    ###If no new name specified, use existing name
    if ($NewScheduleName -like "" -or $NewScheduleName -eq $null) {$NewScheduleName = $ScheduleName}

    Write-Verbose "Deleting old schedule..."	
	$ScheduleParameters = @{
        SubscriptionId = $subscriptionid
        ScheduleName = $ScheduleName
        RequestorUserAccount = $RequestorUserAccount
        ConfigurationItemId = $ConfigurationItemId
    }
    $DeleteOldSchedule = Start-AzureRmAutomationRunbook -Name "Remove-ScheduledVMAction" -Parameters $ScheduleParameters -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount -wait

    Write-Verbose $($DeleteOldSchedule -join " : ")
    if ([string]$DeleteOldSchedule -notmatch "SUCCESS*") {
        throw "Error while deleting old schedule with Schedulename ${ScheduleName}"
    }

    Write-Verbose "Creating new schedule"
	$ScheduleParameters = @{
        SubscriptionId = $subscriptionid
        ScheduleName = $NewScheduleName
		VirtualMachineNames = $VirtualMachineNames
		ScheduleStart = $ScheduleStart
		TimeZone = $TimeZone
		WeekDays = $WeekDays
		ScheduleExpiration = $ScheduleExpiration
		ScheduleAction = $ScheduleAction
        RequestorUserAccount = $RequestorUserAccount
        ConfigurationItemId = $ConfigurationItemId
    }
	$CreateNewSchedule = Start-AzureRmAutomationRunbook -Name "New-ScheduledVMAction" -Parameters $ScheduleParameters -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount -wait
	
    Write-Verbose $($CreateNewSchedule -join " : ")    
    if ([string]$CreateNewSchedule -notmatch "SUCCESS*") {
        throw "Error in creating new schedule with Schedulename ${newScheduleName}"
    }

    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}
    
Write-Output $status
Write-Output $returnMessage
