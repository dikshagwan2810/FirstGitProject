<#
    .SYNOPSIS
        One-line summary

    .DESCRIPTION
        Detailed description

    .OUTPUTS
        Outputs, if any

    .NOTES
        Author:     FIRSTNAME LASTNAME
        Company:    Atos
        Email:      firstname.lastname@atos.net
        Created:    YYYY-MM-DD
        Updated:    YYYY-MM-DD
        Version:    0.1
#>

#Requires -Modules Atos.RunbookAutomation
Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $VirtualMachineResourceGroupName,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String][ValidateNotNullOrEmpty()]
    $ConfigurationItemId

    # Other parameter validation examples:

    # Ensure that the parameter is one of the listed set
    # [ValidateSet('Rod','Jane','Freddy')]
    # [string]$vSet,

    # Empty strings are OK, null values are rejected
    # [ValidateNotNull()]
    # [string]$notNull,

    # The length of the string must be between 1 and 5 characters
    # [ValidateLength(1,5)]
    # [string]$vlength,

    # The integer value of the parameter must be between 10 and 20
    # [ValidateRange(10,20)]
    # [int]$range,

    # The parameter value must pass the regular expression pattern.  In this case, a MAC address
    # [ValidatePattern('^([a-fA-F0-9]{2}[:-]){5}[a-fA-F0-9]{2}$')]
    # [string]$pattern,

    # The parameter value must allow the validation script to return $true to be acceptable
    # [ValidateScript({$_ -eq 'Hello'})]
    # [string]$vScript
)

# Everything wrapped in a try/catch to ensure SNow-compatible output
try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    #-----------------------------------------------------------------------
    # The $Runbook object contains the following properties
    # $Runbook.ResourceGroup
    #     The name of the Runbook Resource Group
    # $Runbook.AutomationAccount
    #     The name of the Runbook Automation Account
    # $Runbook.StorageAccount
    #     The name of the Runbook Storage Account
    # $Runbook.Connections
    #     The value of the RunAsConnectionRepository automation variable
    # $Runbook.JobId
    #     The Job ID of this runbook job
    # $Runbook.Configuration
    #     The MPCAConfiguration JSON object
    #-----------------------------------------------------------------------

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections | Out-Null

    # Code that must be run under the CUSTOMER context goes here




    # $returnStatus should be 'SUCCESS' or 'FAILURE'
    $returnStatus = 'SUCCESS'
    # $returnMessage can be either a simple string or an array of strings.
    $returnMessage = '--> REPLACE WITH SUITABLE SUCCESS MESSAGE <--'
} catch {
    $returnStatus = 'FAILURE'
    Write-Verbose "Fatal error: $($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber), $($_.InvocationInfo.OffsetInLine)]"
    $returnMessage = $_.ToString()
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage