#Requires -Modules Atos.RunbookAutomation

<#
   .SYNOPSIS
     Sript to remove the AvailabilitySet

   .DESCRIPTIONS
     Script to remove the specified AvailabilitySet

   .OUTPUTS
     Displays processes step by step

   .NOTES
     Author:     Diksha Agwan
     Company:    Atos
     Email:      diksha.agwan@atos.net
     Created:    2017-07-17
     Updated:    2017-07-18
     Version:    1.1
#>

Param(
  # The ID of the subscription to use
  [Parameter(Mandatory=$true)]
  [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
  $SubscriptionId,

  #Specify AvailabilitySet Name
  [parameter(Mandatory=$true)]
  [String][ValidateNotNullOrEmpty()]
  $AvailabilitySetResourceGroupName,

  #The name of the Resource Group that the AVSet is in
  [Parameter(Mandatory=$true)]
  [String][ValidateNotNullOrEmpty()]
  $AvailabilitySetName,

  # The ID of the subscription to use
  [Parameter(Mandatory=$true)]
  [String][ValidateNotNullOrEmpty()]
  $RequestorUserAccount,

  # The ID of the subscription to use
  [Parameter(Mandatory=$true)]
  [String][ValidateNotNullOrEmpty()]
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

  #Validation of Resource Group
  $ResourceGroup = Get-AzureRmResourceGroup -Name $AvailabilitySetResourceGroupName
  if (($ResourceGroup -eq $null) -or ($ResourceGroup -eq "")) {
    throw "ResourceGroupName: ${AvailabilitySetResourceGroupName} not found."
  }
  #End of Validation of AvailabilitySetResourceGroupName


  #Validation of AvailabilitySet
  $AVSet = Get-AzureRMAvailabilitySet -ResourceGroupName $AvailabilitySetResourceGroupName -Name $AvailabilitySetName
  if (($AVSet -eq $null) -or ($AVSet -eq "")){
    throw "AvailabilitySetName: ${AvailabilitySetName} not found."
  }
  #End of Validation of AvailabilitySet


  #Validation of VMs in AvailabilitySet
  if ($AVSet.VirtualMachinesReferencesText -match "id") {
    throw "Availability Set ${AvailabilitySetName} can not be deleted. Before deleting an Availability Set please ensure that it does not contain a VM."
  } else {
    $RemoveAVSet = $AVSet | Remove-AzureRmAvailabilitySet -Force
    if ($RemoveAVSet.IsSuccessStatusCode -like "True") {
      $resultMessage = "AvailabilitySet: ${AvailabilitySetName} removed successfully."
      $status = "SUCCESS"
    } else {
      $resultMessage = "AvailabilitySet: ${AvailabilitySetName} was not removed."
      $status = "FAILURE"
    }
  }

} catch {
  $status = "FAILURE"
  $resultMessage = $_.ToString()
}

Write-Output $status
Write-Output $resultMessage
