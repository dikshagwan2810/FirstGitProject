#Requires -Modules Atos.RunbookAutomation

<#
	.SYNOPSIS
    This script adds tags to a specified resource group and storage account(s) in that resourcegroup.
	
	.DESCRIPTION
    - Add below tags to a resoource group based on values provided by user while submitting new resource creation request or update request.
        Project Name: 
        Application Name: 
        ManagedOS: 
        SupportGroup: 
        CI: 
        Environment: from RM
        Costcenter: 
        ControlledByAtos: Unprotected

	.OUTPUTS
    Displays processes step by step during execution
	
	.NOTES
    Author:     Arun Sabale & Peter Lemmen
    Company:    Atos
    Email:      Arun.sabale@atos.net
    Created:    2017-02-18
    Updated:    2017-04-12
    Version:    1.2  
	
	.Note 
	Enable the Log verbose records of runbook
	1.1 Completely rewriten by Peter Lemmen
    1.2 Refactored to use module and harmonise parameters
#>

param(
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String] $SubscriptionId,

    # The name of the Resource Group to update
    [Parameter(Mandatory=$true)]
    [String] $ResourceGroupName,

    # The value for the environment tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String] $Environment,

    # The value for the supportGroup tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String] $SupportGroup,

    # The value for the costCenter tag.  Leave blank to leave unchanged.
    [Parameter(Mandatory=$false)]
    [String] $CostCenter,

    # The value for the projectName tag.  Leave blank to leave unchanged.
	[Parameter(Mandatory=$false)]
	[String] $ProjectName,

    # The value for the appName tag.  Leave blank to leave unchanged.
	[Parameter(Mandatory=$false)]
    [String] $AppName,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

$resultMessage = @()

try {
	# Input Validation
	if (([string]::IsNullOrEmpty($SubscriptionId))) {throw "Input parameter SubscriptionId missing"} 
	if (([string]::IsNullOrEmpty($ResourceGroupName))) {throw "Input parameter ResourceGroupName missing"} 
	if ($Environment.Length -gt 256) {throw "Input parameter Environment has a limitation of 256 characters"}
	if ($SupportGroup.Length -gt 256) {throw "Input parameter SupportGroup has a limitation of 256 characters"}
	if ($CostCenter.Length -gt 256) {throw "Input parameter CostCenter has a limitation of 256 characters"}
	if ($ProjectName.Length -gt 256) {throw "Input parameter ProjectName has a limitation of 256 characters"}
	if ($AppName.Length -gt 256) {throw "Input parameter Appname has a limitation of 256 characters"}
	if ($RequestorUserAccount.Length -gt 256) {throw "Input parameter RequestorUserAccount has a limitation of 256 characters"}
	if ($ConfigurationItemId.Length -gt 256) {throw "Input parameter ConfigurationItemId has a limitation of 256 characters"}

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

    # Start ...
    # Retrieving ResourceGroup information
    $ResourceGroupId = (Get-AzureRmResourceGroup -Name $ResourceGroupName).resourceid

    if ($ResourceGroupId) {
		#Existing tags are retrieved to keep/restore values if needed
	    $ExistingTags =  (Get-AzureRmResourceGroup -Name $ResourceGroupName).Tags

        if ($ExistingTags -ne $null) {
            # Environment, RequestorUserAccount and CI should be preserved if not explicitly overwritten
            if (!([string]::IsNullOrEmpty($Environment))) {
                $tags += @{Environment=$Environment} 
            } else {
                if (!([string]::IsNullOrEmpty($ExistingTags.Item('Environment')))) {
                    $tags += @{Environment=$ExistingTags.Item('Environment')}
                }
            }

            if (!([string]::IsNullOrEmpty($RequestorUserAccount))) {
                $tags += @{UserAccount=$RequestorUserAccount} 
            } else {
                if (!([string]::IsNullOrEmpty($ExistingTags.Item('UserAccount')))) {
                    $tags += @{UserAccount=$ExistingTags.Item('UserAccount')} 
                }
            }

            if (!([string]::IsNullOrEmpty($ConfigurationItemId))) {
                $tags += @{CI=$ConfigurationItemId} 
            } else {
                if (!([string]::IsNullOrEmpty($ExistingTags.Item('CI')))) {
                    $tags += @{CI=$ExistingTags.Item('CI')} 
                }
            }
        } else {
            if (!([string]::IsNullOrEmpty($Environment))) {$tags += @{Environment=$Environment} }
            if (!([string]::IsNullOrEmpty($RequestorUserAccount))) {$tags += @{UserAccount=$RequestorUserAccount} }
            if (!([string]::IsNullOrEmpty($ConfigurationItemId))) {$tags += @{CI=$ConfigurationItemId} }
        }

		# Support, CostCenter, Projectname & AppName can be updated or removed (if not specified) by users
		if (!([string]::IsNullOrEmpty($SupportGroup))) {$tags += @{SupportGroup=$SupportGroup} }
		if (!([string]::IsNullOrEmpty($CostCenter))) {$tags += @{CostCenter=$CostCenter} }
		if (!([string]::IsNullOrEmpty($ProjectName))) {$tags += @{ProjectName=$ProjectName} }
		if (!([string]::IsNullOrEmpty($AppName))) {$tags += @{AppName=$AppName} }

		#ControlledByAtos is always added as tag and always with value unprotected               
		$tags += @{ControlledByAtos="Unprotected"}

		$result = Set-AzureRmResourceGroup -Tag  $tags -Id $ResourceGroupId

		$StorageAccountList = (Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName).StorageAccountName
        foreach ($StorageAccount in $StorageAccountList) {
            Write-Verbose "updating tags for storageaccount: ${StorageAccount}"
			$result = Set-AzureRmResource -Tag $tags -ResourceName $StorageAccount -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.Storage/storageAccounts -Force
        }
      
		$status = "SUCCESS"
		$resultMessage += "For the following azure resources tags were updated successfully:"
		$resultMessage += "Resource group: ${ResourceGroupName}"
        foreach ($StorageAccount in $StorageAccountList) {
			$resultMessage += "Storage account: ${StorageAccount}"
        }
    } else {
		throw "ResourceGroupName: ${ResourceGroupName} not found."
    }
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage