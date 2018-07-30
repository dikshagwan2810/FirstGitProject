#Requires -Modules Atos.RunbookAutomation
<# 
  .SYNOPSIS
    Script to create new automated schedule for the Invoke-VmAction.
  
  .DESCRIPTION
    Script to create new automated schedule for the Invoke-VmAction runbook.
    It will accept the required parameters and provide to the  runbook as well.
    The Invoke-VmAction in turn will start, stop or restart multiple VMs in parallel.
 	 
  .INPUTS
   $SubscriptionID = THe subscription ID of the subscription, of which all the VMs will be part of.
   $VirtualMachineNames = Names of the Azure VMs, in comma separated format, for which the schedule is to be set.
   $ScheduleName = Name of the newly created schedule.
   $ScheduleStart = Time for the schedule on which the schedule should run.
   $ScheduleExpiration = Expiration date for schedule.
   $TimeZone = TimeZone of the specified input ScheduleTime and StartDate.
   $WeekDays = Days of the week on which the schedule should run, comma-separated.
   $ScheduleAction = Action to be performed, either to start, stop, or restart the VMs specified.
   $RequestorUserAccount = Account name of the user.
   $ConfigurationItemId = Configuration item ID.
  
  .OUTPUTS
    Displays processes step by step during execution
  
  .NOTES
    Author:     Austin Palakunnel, Rashmi Kanekar, Russell Pitcher
    Company:    Atos
    Email:      austin.palakunnel@atos.net
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

    [Parameter(Mandatory=$true)] 
    [String] 
    $VirtualMachineNames,

    [Parameter(Mandatory=$true)] 
    [String] 
    $ScheduleName,

    [Parameter(Mandatory=$true)] 
    [String] 
    $ScheduleStart,

    [Parameter(Mandatory=$false)] 
    [String] 
    $ScheduleExpiration,

    [Parameter(Mandatory=$true)] 
    [String] 
    $TimeZone,

    [Parameter(Mandatory=$true)] 
    [String] 
    $WeekDays,

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
    $ErrorState = 0
    $returnMessage = ""

    $KeyName = "atosMaintenanceString1"

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

    #Validation of Schedule Name
    if ($ScheduleName -match "^[a-zA-Z0-9 ]*$") {
		Write-Verbose "Correct Resource Group name"
	} else {
        Throw "Schedule Name specified contains special characters. Only aplhanumeric characters are allowed"
    }

    if($ScheduleName.Length -gt 128) {
        Throw "Maximum length of ScheduleName is 128 characters."
    }

    $ScheduleAction = $ScheduleAction.Trim()
    if ($ScheduleAction -notlike "Start-VM" -and $ScheduleAction -notlike "Stop-VM" -and $ScheduleAction -notlike "Restart-VM" -and $ScheduleAction -notlike "Enable-MaintenanceMode" -and $ScheduleAction -notlike "Disable-MaintenanceMode") {
        throw "Invalid input for ScheduleAction : ${ScheduleAction}"
    }
    
    try {
        $StartDateTime = [datetime]::ParseExact("$ScheduleStart","yyyy-M-d H:m:s",$null)
    } catch {
        throw "Invalid input for ScheduleStart : ${ScheduleStart}"
    }

    if ($($StartDateTime.ToUniversalTime()) -le $([datetime]::UtcNow.AddHours(1))) {
        throw "Invalid input for ScheduleStart : ${ScheduleStart}. Specify a datetime at least 1 hour past the current date/time"
    }
    
    if ($ScheduleExpiration -ne $null -and $ScheduleExpiration -notlike "") {
        $UseExpireDate = $true
        try {
            $EndDateTime = [datetime]::ParseExact("$ScheduleExpiration","yyyy-M-d H:m:s",$null)
        } catch {
            throw "Invalid input for ScheduleExpiration : $ScheduleExpiration"
        }

        if ($($EndDateTime.ToUniversalTime()) -le $([datetime]::UtcNow.AddHours(1))) {
            throw "Invalid input for ScheduleExpiration : ${ScheduleExpiration}. Specify a datetime at least 1 hour past the current date/time"
        }
    }

    $TimeZoneCheck = [timezoneinfo]::GetSystemTimeZones() | Where-Object {$_.id -eq $TimeZone}
    if ($TimeZoneCheck -eq $null) {
        throw "Invalid input for TimeZone : ${TimeZone}"
    }
            
    if ($UseExpireDate -eq $true) {
         $TimeZoneOffset = [timezoneinfo]::FindSystemTimeZoneById($TimeZone)
        [datetime]$EndDateTime = $EndDateTime.Add($TimeZoneOffset.BaseUtcOffset)
    } else {
        [datetime]$EndDateTime = "01-01-9999"
    }
    ##End of validation section

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    Write-Verbose "Checking if schedule with same name already exists."
    try {
        $ScheduleCheck = Get-AzureRmAutomationSchedule -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount | Where-Object {$_.Name -like $ScheduleName}
    } catch  {
        ## Nothing to do. Error expected if no schedule found
        # Write-Verbose $_.Exception.GetType().FullName
    }
    if ($ScheduleCheck -ne $null) {
        throw "Schedule with name ${ScheduleName} already exists. Please provide a unique name for schedule."
    }

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    $TagName = $ScheduleName
    $LocalTimeZone = [timezoneinfo]::GetSystemTimeZones() | Where-Object {$_.id -like "$TimeZone"}   
    $StartDateTimeUTC = [System.TimeZoneInfo]::ConvertTimeToUtc($StartDateTime, $LocalTimeZone)

    ###Code to fetch all VMs based on particular TagName
    $ListOfVMs = @()
    $ListOfVMs = Get-AzureRmVM -WarningAction SilentlyContinue
    
    $VirtualMachineNamesArray = $VirtualMachineNames.Split(",")
    $VMsforNewSchedule = @()
    $VMsforNewSchedule = $ListOfVMs | Where-Object {$_.Name -in $VirtualMachineNamesArray}

    foreach ($VM in $ListOfVMs) {
        if ($VM.Name -notin $VirtualMachineNamesArray) {
            $TagValue = $VM.Tags["$KeyName"]
            if ($TagValue -match "^([a-zA-Z_\s$-?]+,)*\s*$TagName\s*(,[a-zA-Z_\s$-?]+)*$") {
                throw "Schedule Name ${TagName} already in use for VM $($VM.Name)"
            }
        }
    }
           
    Write-Verbose "Adding tags for VMs."
    foreach ($VM in $VMsforNewSchedule) {
        Write-Verbose "Creating a new tag for VM $($VM.Name)"
        $Tags = $VM.Tags
        $TagValue = $Tags["$KeyName"]
        
        if ($TagValue -notmatch "^([a-zA-Z_\s$-?]+,)*\s*$TagName\s*(,[a-zA-Z_\s$-?]+)*$") {
            ##If key does not exist, add it
            $NewTagValue = ""
            if ($TagValue -eq $null -or $TagValue -like "") {
                $NewTagValue = "$TagName"
                $Tags.Add("$KeyName","$NewTagValue") #| Out-Null
            } else {
                ###Update existing key
                $NewTagValue = "${TagValue},${TagName}"
                $Tags["$KeyName"]="$NewTagValue"
            }

            # Validate Tag Length
            if ($Tags[$KeyName].Length -gt 256) {
                Throw "The tag: $($Tags[$KeyName]) exceeds 256 characters, the current length is $($Tags[$KeyName].length)."
            }

            ##Set Tags to VM
            $SetTagOeration = Set-AzureRmResource -ResourceId $VM.Id -Tag $Tags -Force
            Write-Verbose $SetTagOeration
        }
    }

    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Creating new schedule."
    $NewlyCreatedSchedule = New-AzureRmAutomationSchedule -Name "$ScheduleName" -StartTime $StartDateTimeUTC -DaysOfWeek $WeekDaysArray -ExpiryTime $EndDateTime -Description "$TagName" -ResourceGroupName $Runbook.ResourceGroup -AutomationAccountName $Runbook.AutomationAccount -WeekInterval 1 -ErrorAction Stop
    Write-Verbose $NewlyCreatedSchedule
    $Parameters = @{
        VirtualMachineAction = "$ScheduleAction"
        TagName = "$TagName"
        SubscriptionID = "$SubscriptionId"
    }
    $RegisterRunbookOperation = Register-AzureRmAutomationScheduledRunbook -RunbookName "Invoke-VmAction" -ScheduleName "$ScheduleName" -Parameters $Parameters -AutomationAccountName $Runbook.AutomationAccount -ResourceGroupName $Runbook.ResourceGroup -ErrorAction Stop
    Write-Verbose $RegisterRunbookOperation
    Write-Verbose "Registered runbook to run for schedule ${ScheduleName}"
    
    $status = "SUCCESS"
    $returnMessage = "Registered runbook to run for schedule ${ScheduleName}"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage
