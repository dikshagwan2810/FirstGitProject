<#
    .SYNOPSIS
        This script can be used to clear the DoNotDelete Tags on resource groups created by Onboarding.

    .DESCRIPTION
        This script is typically used just before the Remove-Environment (Cleanup) script is executed so all Onboarding resource groups that should be removed have their 'DoNotDelete' tag removed.

    .OUTPUTS
        None

    .NOTES
        Author:     PETER LEMMEN
        Company:    Atos
        Email:      peter.lemmen@atos.net
        Created:    2017-11-07
        Updated:    2017-11-07
        Version:    0.1
#>

#Requires -Modules Atos.RunbookAutomation
Param (
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('full','partial')]
    [System.String]$global:CleanUpMode
)

function Clear-Tags-Management {

    $ResourceGroupList = @()
	$customercode = $Runbook.Configuration.Customer.NamingConventionSectionA

    if ($global:CleanUpMode -eq 'full') {
        $resourcegroups = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "*-$customercode-automation*"}
    }
    else
    {
        $resourcegroups = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "*-$customercode-automation"}
    }

    foreach ($resourcegroup in $resourcegroups)
    {
        $ResourceGroupList += $resourcegroup.ResourceGroupName
    }

    foreach ($resourcegroup in $ResourceGroupList)
    {
		Set-AzureRmResourceGroup -Name $resourcegroup -Tag @{} | Out-Null
		Write-Verbose "All tags have been removed from resource group: $resourcegroup"
    }
}

function Clear-Tags-Customer {

    $ResourceGroupList = @()

	$resourcegroups = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "*-rsg-omsworkspace"}

    foreach ($resourcegroup in $resourcegroups)
    {
        $ResourceGroupList += $resourcegroup.ResourceGroupName
    }

    $resourcegroups = Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "*-rsg-network"}

    foreach ($resourcegroup in $resourcegroups)
    {
        $ResourceGroupList += $resourcegroup.ResourceGroupName
    }

    foreach ($resourcegroup in $ResourceGroupList)
    {
		Set-AzureRmResourceGroup -Name $resourcegroup -Tag @{} | Out-Null
		Write-Verbose "All tags have been removed from resource group: $resourcegroup"
    }
}

# Everything wrapped in a try/catch to ensure SNow-compatible output
try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
	
	Clear-Tags-Management

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

	if ($global:CleanUpMode -eq 'Full')
	{
		foreach ($Subscription in $Runbook.Configuration.Subscriptions)
		{
			# Switch to customer's subscription context
			Write-Verbose "Connect to customer subscription"
			Connect-AtosCustomerSubscription -SubscriptionId $Subscription.Id -Connections $Runbook.Connections | Out-Null

			# Code that must be run under the CUSTOMER context goes here
			Clear-Tags-Customer
		
		}
	}
    # $returnStatus should be 'SUCCESS' or 'FAILURE'
    $returnStatus = 'SUCCESS'
    # $returnMessage can be either a simple string or an array of strings.
    $returnMessage = 'Done with the removal of DoNotDelete tags.'
} catch {
    $returnStatus = 'FAILURE'
    Write-Verbose "Fatal error: $($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber), $($_.InvocationInfo.OffsetInLine)]"
    $returnMessage = $_.ToString()
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage