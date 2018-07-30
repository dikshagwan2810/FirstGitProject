#Requires -Modules Atos.RunbookAutomation

<#
    .SYNOPSIS
    This script creates new Managed Availabilty Set.
    
    .DESCRIPTION
    - Generates the Availability Set as per the naming convention.
    - Validates the fault domain and update domain count as per the region to be placed in.
    - Checks whether the availability set is unique in the specified resource group
    - Creates new managed Availability set in the specified Resource Group
    
    .NOTES
    Author:     Rashmi Kanekar
    Company:    Atos
    Email:      rashmi.kanekar@atos.net
    Created:    2017-07-17
    Version:    1.0
    
    .Note 
    1.0 - Creates the managed Availability Set as per the region specific configuration for fault and update domain
#>

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String] [ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')] [ValidateNotNullOrEmpty()]
    $SubscriptionId,

    # The name of the availability set to act upon
    [Parameter(Mandatory=$true)]
    [String] [ValidatePattern('^([a-zA-Z0-9])($|([a-zA-Z0-9\-_]){0,62}[a-zA-Z0-9_]{1}$)')] [ValidateNotNullOrEmpty()]
    $AvailabilitySetName,

    # The name of the Resource Group that the availability set is in
    [Parameter(Mandatory=$true)]
    [String] [ValidateNotNullOrEmpty()]
    $AvailabilitySetResourceGroupName,

    # The name for the new disk.  This will be combined with the VM name, and a counter if necessary, to ensure a unique name
    [Parameter(Mandatory=$true)] 
    [String] [ValidateNotNullOrEmpty()]
    $AvailabilitySetLocation,

    # The value for update domain
    [Parameter(Mandatory=$true)] 
    [int] [ValidatePattern('^(0*[1-9][0-9]*)$')] [ValidateNotNullOrEmpty()]
    $UpdateDomainCount,

    # The value for fault domain
    [Parameter(Mandatory=$true)] 
    [int][ValidatePattern('^(0*[1-9][0-9]*)$')] [ValidateNotNullOrEmpty()]
    $FaultDomainCount,

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

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    # Performing Resource Group Check
    Write-Verbose "Performing Resource Group Check for resource group ${AvailabilitySetResourceGroupName}"
    $ResourceGroupInfo = Get-AzureRmResourceGroup -Name $AvailabilitySetResourceGroupName
    if ($ResourceGroupInfo -eq $null) 
    {
        throw "Resource Group Name ${AvailabilitySetResourceGroupName} not found"
    }

    # Naming Convention Check
    Write-Verbose "Performing Availability Set Naming convention check on input $AvailabilitySetName"
    if ($AvailabilitySetName -notmatch  "^([a-zA-Z0-9])($|([a-zA-Z0-9\-_]){0,62}[a-zA-Z0-9_]{1}$)")
    {
        throw "$AvailabilitySetName contains invalid character. Vaild characters are alphanumeric, underscore, and hyphen"
    }

    # Retrieve Availability Set Name prefix
    Write-Verbose "Retrieving the naming prefix from Resource Group Name"
    $PrefixName = ($AvailabilitySetResourceGroupName.Substring(0,10)).ToLower() + "-aas-"

    # Generate Availability Set as per naming standard
    Write-Verbose "Generate Availability Set as per naming standard"
    $StandardAvailabilitySetName = ($PrefixName + $AvailabilitySetName).ToLower()

    # Availability Set Name check
    Write-Verbose "Performing check whether the Availability Set $StandardAvailabilitySetName already exists in Resource Group $AvailabilitySetResourceGroupName"
    $AvailabilitySetNameCheck = Get-AzureRmAvailabilitySet -ResourceGroupName $AvailabilitySetResourceGroupName | Where-Object {$_.name -like $StandardAvailabilitySetName}
    if(!($AvailabilitySetNameCheck -eq $null -or $AvailabilitySetNameCheck -eq ""))
    {
        throw "Availability Name : $StandardAvailabilitySetName already exists in resource group name $AvailabilitySetResourceGroupName"
    }

    # Location Check
    Write-Verbose "Check whether the location : $AvailabilitySetLocation is valid"
    $LocationCheck = ($Runbook.Configuration.AvailabilitySets.MaxFaultDomainCount | Where-Object {$_.Region -like "$AvailabilitySetLocation"}).region
    if ($LocationCheck -eq $null -or $LocationCheck -eq "")
    {
        throw "Location specified $AvailabilitySetLocation is not available."
    }


    # Update Domain Count Check
    Write-Verbose "Validate the update domain count value : $UpdateDomainCount"
    $MaxUpdateDomainCount = $Runbook.Configuration.AvailabilitySets.MaxUpdateDomainCount
    if($UpdateDomainCount -gt $MaxUpdateDomainCount)
    {
        throw "Max Update Domain Count for region $AvailabilitySetLocation is $MaxUpdateDomainCount."
    }


    # Fault Domain Count Check 
    Write-Verbose "Validate the fault domain count value : $UpdateDomainCount as per max domain count for the specified region"
    $MaxFaultDomainCount = ($Runbook.Configuration.AvailabilitySets.MaxFaultDomainCount | Where-Object {$_.Region -like "$AvailabilitySetLocation"}).count
    if ($FaultDomainCount -gt $MaxFaultDomainCount)
    {
        throw "Max Fault Domain Count for region $AvailabilitySetLocation is $MaxFaultDomainCount"
    }

    # Create Availability Set 
    Write-Verbose "Create the new availability set..."
    $AvailabilitySetInfo = New-AzureRmAvailabilitySet -ResourceGroupName $AvailabilitySetResourceGroupName `
                                -Name $StandardAvailabilitySetName `
                                -Location $AvailabilitySetLocation `
                                -PlatformUpdateDomainCount $UpdateDomainCount `
                                -PlatformFaultDomainCount $FaultDomainCount `
                                -Sku Aligned


    $status = "SUCCESS"
    $resultMessage ="Availability Set : $StandardAvailabilitySetName created successfully."
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
