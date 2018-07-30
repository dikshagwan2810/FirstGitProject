#Requires -Modules Atos.RunbookAutomation
<#
  .SYNOPSIS
    Script to delete resource group.
  
  .DESCRIPTION
    Script to delete resource group.
    The script handles multiple subscriptions.
    The script will delete the resource group along with all the associated resources
    It will also delete an associated Recovery Services Vault unless there remain restore points within that vault
  
  .NOTES
    Author:     Ankita Chaudhari, Russ Pitcher
    Company:    Atos
    Email:      ankita.chaudhari@atos.net
    Created:    2016-12-01
    Updated:    2017-04-12
    Version:    1.1
   
   .Note 
        Enable the Log verbose records of runbook 
#>

Param (
    # The ID of the subscription containing the resource group
    [Parameter(Mandatory=$true)] 
    [String] 
    $SubscriptionId,

    # The name of the resource group to be deleted
    [Parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

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
    if ([string]::IsNullOrEmpty($ResourceGroupName)) {throw "Input parameter: ResourceGroupName missing."}
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

    #Validation of Resource Group
    $ResourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName
    if (($ResourceGroup -eq $null) -or ($ResourceGroup -eq "")) {
        throw "ResourceGroupName: ${ResourceGroupName} not found."
    }
    $ResourceGroupLocation = $ResourceGroup.Location
    #End of Resource Group validation

    #Remove Resource Group
    $DeleteRG = $ResourceGroup | Remove-AzureRmResourceGroup -Force
    if ($DeleteRG -like "True") {
        $resultMessage = "ResourceGroup: ${ResourceGroupName} removed successfully."
        $status = "SUCCESS"
    }
    #End of Remove Resource Group
      
} catch {
    $status = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage