#Requires -Modules Atos.RunbookAutomation 
<#
    .SYNOPSIS
    This script delete Load balancer.
   
    .DESCRIPTION
    - delete internal or public load balancer with associated ip


    .INPUTS
        $VirtualMachineResourceGroupName - The name of Resource Group where the VM needs to be created
        $RequestorUserAccount - Contains user account name of snow user
        $LBName - Load balancer short name
        $SubscriptionId - Customer subscription id
        ConfigurationItemId - Configuration Item Id for tracking on UI


    .OUTPUTS
    Displays processes step by step during execution
   
    .NOTES
    Author:     Arun Sabale
    Company:    Atos
    Email:      Arun.sabale@atos.net
    Created:    2017-06-15
    Updated:    2017-06-15
    Version:    1.0
   
    .Note
    Enable the Log verbose records of runbook
    
#>

Param (
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineResourceGroupName,

    [Parameter(Mandatory=$True)]
    [String]
    $LBName,

    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId


)


#start with Try block
try {
    #region Input Validation and connection
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}
    if ([string]::IsNullOrEmpty($LBName)) {throw "Input parameter: LBName missing."}

    # Connect to the management subscription
    write-verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    write-verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    # Switch to customer's subscription context
    write-verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    write-verbose "Received Input:"
    write-verbose "  VirtualMachineResourceGroupName : $VirtualMachineResourceGroupName"
    write-verbose "  LBName : $LBName"
    write-verbose "  SubscriptionId : $SubscriptionId"
    write-verbose "  RequestorUserAccount : $RequestorUserAccount"
    write-verbose "  ConfigurationItemId : $ConfigurationItemId"

    #endregion

    #region check if LB  exist
    $lb = Get-AzureRmLoadBalancer |where{$_.name -eq $LBName} 
    if($lb)
    {
    $publicIPCheck="no"
    $VirtualMachineResourceGroupName =$lb.ResourceGroupName
    
    #remove LB with name and RG
    Remove-AzureRmLoadBalancer -Name $LBName -ResourceGroupName $VirtualMachineResourceGroupName -Force |Out-Null
    if($lb.FrontendIpConfigurations.publicipaddress)
    {
    $publicipname = Get-AzureRmPublicIpAddress -ResourceGroupName $VirtualMachineResourceGroupName |where{$_.Name -like "$LBName*"}
    if($publicipname)
     {
     Remove-AzureRmPublicIpAddress -Name $($publicipname.name) -ResourceGroupName $VirtualMachineResourceGroupName -Force |Out-Null
     $publicIPCheck="yes"
     }
     Else
     {
     throw "Unable to get public ip detail for LB ${$LBName}"
     }
    }

    #verify  public ip
    if($publicIPCheck -eq "Yes")
    {
    $publicip = Get-AzureRmPublicIpAddress -Name $($publicipname.name) -ResourceGroupName $VirtualMachineResourceGroupName -ErrorAction SilentlyContinue
    if($publicip)
    {
    throw "Failed to remove public ip ${LBName} "
    }
    else
    {
     write-verbose "public ip  ${LBName} removed successfully"
    }
    }
    }
    else
    {
      throw "Load balancer ${LBName} does not exist"
    }
    #endregion

    #region re-verify
    $lb = Get-AzureRmLoadBalancer |where{$_.name -eq $LBName} 
    if($lb)
    {
    throw "Failed to remove Load balancer ${LBName} "
    }
    else
    {
     write-verbose "Load balancer ${LBName} removed successfully"
    }
    #endregion

    


	# End of Creating Load balancer
	$status = "SUCCESS"
    $returnMessage = "Load Balancer: $LBName Deleted successfully."
} 
catch 
{
    $status = "FAILURE"
	$returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage

