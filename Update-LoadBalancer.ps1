#Requires -Modules Atos.RunbookAutomation 
<#
    .SYNOPSIS
    This script creates modify Load balancer.
   
    .DESCRIPTION
    - Add VM to existing load balancer 
    - remove VM from existing load balancer 
    - Remove existing backend pool deassociate vm's and load balancer rule from existing load balancer 
    - Add new backend pool with virtual machine and load balancer rule to existing load balancer

    .INPUTS
        $VirtualMachineResourceGroupName - The name of Resource Group where the VM needs to be created
        $VirtualMachineName - The Name of VM service abbreviation
        $RequestorUserAccount - Contains user account name of snow user
        $VirtualNetworkSubnetName - Contains the subnet name of the network specified
        $LBName - Load balancer short name
        $SubscriptionId - Customer subscription id
        $VirtualNetworkResourceGroupName - Network resource group name for LB
        $VirtualNetworkName - Vnet name for LB to take ip from 
        $healthProbePort - Post number for TCP health probe
        $SessionPersistence -  to define Session Persistence
        $LBType - Public or internal
        $LBRuleBackendPort - Load balancer rule backend port number


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

    [Parameter(Mandatory=$false)]
    [String]
    $AvailabilitySet,

    [Parameter(Mandatory=$false)]
    [String]
    $AddVMName,

    [Parameter(Mandatory=$True)]
    [String]
    $LBName,

    [Parameter(Mandatory=$false)]
    [String]
    $RemoveVMName,

    [Parameter(Mandatory=$false)]
    [String]
    $BackendPoolName,

    [Parameter(Mandatory=$false)]
    [String]
    $RemoveBackendPoolName,

    [Parameter(Mandatory=$false)]
    [String]
    $AddBackendPoolName,

    [Parameter(Mandatory=$false)]
    [String]
    $AvailabilitySetChanged,

    [Parameter(Mandatory=$false)]
    [int]
    $healthProbePort,

    [Parameter(Mandatory=$false)]
    [int]
    $AddRulePort,

    [Parameter(Mandatory=$false)]
    [int]
    $AddRuleBackendPort,

    [Parameter(Mandatory=$false)]
    [string]
    $AddRuleProtocol,

    [Parameter(Mandatory=$false)]
    [string]
    $SessionPersistence,

    [Parameter(Mandatory=$false)]
    [int]
    $IdleTimeoutInMinutes,

    [Parameter(Mandatory=$false)]
    [string]
    $AddBackendPoolVMName,

    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId


)


#start with Try block
try {
    #region - Input Validation and Azure connetion
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($LBName)) {throw "Input parameter: LBName missing."}

    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}
        


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
    write-verbose "  SubscriptionId : $SubscriptionId"
    write-verbose "  VirtualNetworkResourceGroupName : $VirtualNetworkResourceGroupName"
    write-verbose "  LBName : $LBName"
    write-verbose "  AvailabilitySet : $AvailabilitySet"
    write-verbose "  AddVMName : $AddVMName"
    write-verbose "  RemoveVMName : $RemoveVMName"
    write-verbose "  RemoveBackendPoolName : $RemoveBackendPoolName"
    write-verbose "  AddBackendPoolName : $AddBackendPoolName"
    write-verbose "  AvailabilitySetChanged : $AvailabilitySetChanged"
    write-verbose "  healthProbePort : $healthProbePort"
    write-verbose "  AddRulePort : $AddRulePort"
    write-verbose "  AddRuleBackendPort : $AddRuleBackendPort"
    write-verbose "  AddRuleProtocol : $AddRuleProtocol"
    write-verbose "  SessionPersistence : $SessionPersistence"
    write-verbose "  IdleTimeoutInMinutes  : $IdleTimeoutInMinutes"
    write-verbose "  AddBackendPoolVMName  : $AddBackendPoolVMName"
    write-verbose "  RequestorUserAccount : $RequestorUserAccount"
    write-verbose "  ConfigurationItemId : $ConfigurationItemId"
    
    #endregion

    #region - Performing Resource Group Check
    write-verbose "Performing Resource Group Check for resource group ${VirtualMachineResourceGroupName}"
    $ResourceGroupInfo = Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName
    if ($ResourceGroupInfo -eq $null) {
        throw "Resource Group Name ${VirtualMachineResourceGroupName} not found"
    }#endregion

    #region - Remove VM from selected backend pool
    if($RemoveVMName)
    {
    write-verbose "Removing VM from existing load balancer $LBName"
    [array]$RemoveVMName = $RemoveVMName.Split(",")
    if($BackendPoolName -notlike "$LBName*")
    {
    $BackendPoolName = $LBName+"-"+$BackendPoolName
    }
    #check if LB exist 
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    if($lb)
    {
    Write-Verbose "Load balancer $LBName exist"
    }
    else
    {
    throw "Load balancer $LBName does NOT exist"
    }
    #check if VM exist
    foreach($RemoveVMName1 in $RemoveVMName)
    {
    $Vm = get-azurermvm |where{$_.Name -eq $RemoveVMName1}
    if (!$Vm) {
        throw "VMNames: ${$RemoveVMName1} does not exist!"
    }
    }

    foreach($RemoveVMName1 in $RemoveVMName)
    {
    #get vm netword interface
    write-verbose "removing $RemoveVMName1 from LB"
    $vm1= get-azurermvm |where{$_.Name -eq $RemoveVMName1}
    $VMvnic = ($vm1.NetworkProfile.NetworkInterfaces.id).split("/")
    $VMvnicName= $VMvnic[($VMvnic.Length -1)]

    #remove network interface to lb
    write-verbose "removing $VMvnicName from LB"
    $nic = Get-AzureRmNetworkInterface -Name $VMvnicName -ResourceGroupName $($vm1.ResourceGroupName)
    $count =0
    
    foreach($LoadBalancerBackendAddressPool1 in $nic.IpConfigurations[0].LoadBalancerBackendAddressPools)
    {
    if ($LoadBalancerBackendAddressPool1.Id -like "*$BackendPoolName")
    {
    If($count -gt 0)
    {
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools[$count]=$null
    write-verbose "removing vnic position $count"
    }
    elseif($count -eq 0)
    {
    write-verbose "vm is part of one backend pool"
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools=$null
    }
    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
    if($setnic)
    {
    write-verbose "REmoved vm $RemoveVMName1 from  ${$LBName}"
    }
    else
    {
    throw "Remove VM from LB: unable to Remove VM ${$RemoveVMName1} from  ${$LBName} "
    }
    }
    $count=$count+1
    }
    }
    #final result    
    $status = "SUCCESS"
    $returnMessage = "Remove VM: $RemovevmName removed successfully from backend pool $BackendPoolName."
    } 
    #endregion

    #region - add vm to selected backend pool
    If($AddVMName)
    {
    write-verbose "Adding VM to existing load balancer $LBName"
    [array]$AddVMName = $AddVMName.Split(",")
    if($BackendPoolName -notlike "$LBName*")
    {
    $BackendPoolName = $LBName+"-"+$BackendPoolName
    }
    #check if LB exist 
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    if($lb)
    {
    Write-Verbose "Load balancer $LBName exist"
    }
    else
    {
    throw "Load balancer $LBName does NOT exist"
    }

    #check if VM exist
    foreach($AddVMName1 in $AddVMName)
    {
    $Vm = get-azurermvm |where{$_.Name -eq $AddVMName1}
    if (!$Vm) 
    {
        throw "VMNames: ${$AddVMName1} does not exist!"
    }
    }
    foreach($AddVMName1 in $AddVMName)
    {
     #get vm netword interface
    $vm1= get-azurermvm |where{$_.Name -eq $AddVMName1}
    $VMvnic = ($vm1.NetworkProfile.NetworkInterfaces.id).split("/")
    $VMvnicName= $VMvnic[($VMvnic.Length -1)]

    #add network interface to lb
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    $backend = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb |where{$_.name -like "*$BackendPoolName"}
    if(!($backend))
    {
    throw "Unable to find backend pool $BackendPoolName"
    }
    $MemberExist = "no"
    foreach($backend1 in $backend.BackendIpConfigurations)
    {
    if($backend1.id -like "*$VMvnicName*")
    {
    write-verbose "VM already part of load balancer $LBName backend pool $BackendPoolName"
    $MemberExist = "Yes"
    }
    }
    if($MemberExist -eq "no")
    {
    $nic = Get-AzureRmNetworkInterface -Name $VMvnicName -ResourceGroupName $($vm1.ResourceGroupName)
    $count = $nic.IpConfigurations[0].LoadBalancerBackendAddressPools.Count
    if ($count -gt 0)
    {
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools+=$backend
    }
    elseif ($count -eq 0)
    {
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools=$backend
    }
    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic 
    if($setnic)
    {
    write-verbose "Added vm $AddVMName1 to  ${$LBName} backend pool ${$BackendPoolName}"
    }
    else
    {
    throw "Add VM to LB: unable to add VM ${$AddVMName1} to  ${$LBName} "
    }
    }
    Else
    {
    write-verbose "VM already exist in backend pool $BackendPoolName"
    }
    }
    #final result    
    $status = "SUCCESS"
    $returnMessage = "Add VM: $AddvmName added successfully to backend pool $BackendPoolName."
    } 
    #endregion
    
    #region - Remove selected backend pool
    if($RemoveBackendPoolName)
    {
    write-verbose "Removing Backend pool $RemoveBackendPoolName from existing load balancer $LBName"
    if($RemoveBackendPoolName -notlike "$LBName*")
    {
    $RemoveBackendPoolName1=$RemoveBackendPoolName
    $RemoveBackendPoolName = $LBName+"-"+$RemoveBackendPoolName
    }
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    $removerulename = $RemoveBackendPoolName.Replace("lbal","lbrc")
    
	$ruleName = $lb.LoadBalancingRules |where{$_.Name -eq "$removerulename"} | select -ExpandProperty name
	
    if($ruleName)
    {
    $removerule = Remove-AzureRmLoadBalancerRuleConfig -Name $ruleName -LoadBalancer $lb 
    }
    $probeName = $lb.Probes |where{$_.Name -like "*$RemoveBackendPoolName*"} | select -ExpandProperty name
    
	if($probeName)
    { 
		#Check if there are multiple Probe names
		if ($probeName.Count -gt 1)
        {
            $removeProbe = Remove-AzureRmLoadBalancerProbeConfig -Name $probeName[0] -LoadBalancer $lb 
        }
        else
        {
           $removeProbe = Remove-AzureRmLoadBalancerProbeConfig -Name $probeName -LoadBalancer $lb 
        }
    }
	
    $beName = $lb.BackendAddressPools |where{$_.Name -like "*$RemoveBackendPoolName*"} | select -ExpandProperty name
   
    if($beName)
    {
	    #Check if there are multiple BackendAddressPool names
        if ($beName.Count -gt 1)
        {
            $removebe = Remove-AzureRmLoadBalancerBackendAddressPoolConfig -Name $beName[0] -LoadBalancer $lb
        }
        else
        {
            $removebe = Remove-AzureRmLoadBalancerBackendAddressPoolConfig -Name $beName -LoadBalancer $lb    
        }
    }
	
    $setLB = Set-AzureRmLoadBalancer -LoadBalancer $lb
    if($setLB)
    {
    write-verbose "removed load balancer backend pool ad rule"
    }
    else
    {
    Throw "Failed to remove new load balancer backend pool $RemoveBackendPoolName or rules"
    }
    #final result    
    $status = "SUCCESS"
    $returnMessage = "Load Balancer Backend pool: $RemoveBackendPoolName removed successfully."
    }
    #endregion

    #region - Add New backend pool to selected load balancer
    if($AddBackendPoolName)
    {
    write-verbose "Adding Backend pool $AddBackendPoolName to existing load balancer $LBName"
    [array]$AddBackendPoolVMName=$AddBackendPoolVMName.Split(",")
    if($AddBackendPoolName -notlike "$LBName*")
    {
    $AddBackendPoolName = $LBName+"-"+$AddBackendPoolName
    }
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    if(!($lb))
    {
    throw "Load balancer $LBName does not exist"
    }
    if ($AvailabilitySetChanged -eq "yes")
    {
    $LBbackendconfig = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb
    if($LBbackendconfig.BackendIpConfigurations)
    {
    throw "Please delete all backend pool first to associate different availability set"
    }
    }
    
    #prepare LB rule name
    $LBFullNameRule = $AddBackendPoolName.Replace("lbal","lbrc")
    $LBFullNameRule=$LBFullNameRule.ToLower()
    if($LBFullNameRule)
    {
    if ($LBFullNameRule.Length -lt 80) {
		write-verbose "Acceptable LB rule name"
	} else {
		throw "LBFullNameRule: ${LBFullNameRule} have more than 80 character."
	}
    }
    else
    {
    throw "LBFullNameRule: ${LBFullNameRule} is invalid."
    }
	#prepare notification LB rule name
	$statuslbrulename = "Load Balancer Rule : $LBFullNameRule `n"
	
    #prepare LB probe name
    $LBPBName = $AddBackendPoolName+"-Probe1"
    $LBPBName=$LBPBName.ToLower()
    if ($LBPBName) 
    {
    if ($LBPBName.Length -lt 80) {
		write-verbose "Acceptable LB probe name"
	} else {
		throw "LBPBName: ${LBPBName} have more than 80 character."
	}
    }
    else
    {
    throw "LBPBName: ${LBPBName} is invalid."
    }
	#prepare notification LB probe name
	$statuslbprobename = "`nLoad Balancer Probe : $LBPBName `n"
	
    #create new LB backend config
    #$beaddresspool = new-AzureRmLoadBalancerBackendAddressPoolConfig -Name $AddBackendPoolName
    $addbeaddresspool= Add-AzureRmLoadBalancerBackendAddressPoolConfig -Name $AddBackendPoolName -LoadBalancer $lb
    $setLB = Set-AzureRmLoadBalancer -LoadBalancer $lb 
    if($setLB)
    {
    write-verbose "updated load balancer backend pool"
    }
    else
    {
    Throw "Failed to create new load balancer backend pool $AddBackendPoolName"
    }
    #add health probe
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    $healthProbe = add-AzureRmLoadBalancerProbeConfig -Name $LBPBName -Protocol tcp -Port $healthProbePort -IntervalInSeconds 15 -ProbeCount 2 -LoadBalancer $lb
    $setLB = Set-AzureRmLoadBalancer -LoadBalancer $lb 
    if($setLB)
    {
    write-verbose "updated load balancer health probe"
    }
    else
    {
    Throw "Failed to create new load balancer backend pool $AddBackendPoolName"
    }
    #Add LB rule
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    $frontendIP = Get-AzureRmLoadBalancerFrontendIpConfig -LoadBalancer $lb
    $healthProbe = get-AzureRmLoadBalancerProbeConfig -Name $LBPBName -LoadBalancer $lb
    $newbeaddresspool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb |where{$_.name -eq $AddBackendPoolName}
    $lbrule = add-AzureRmLoadBalancerRuleConfig -Name $LBFullNameRule -FrontendIpConfiguration $frontendIP -Protocol $AddRuleProtocol -FrontendPort $AddRulePort -BackendPort $AddRuleBackendPort -IdleTimeoutInMinutes $IdleTimeoutInMinutes -LoadDistribution $SessionPersistence -LoadBalancer $lb -BackendAddressPool $newbeaddresspool -Probe $healthProbe
    $setLB = Set-AzureRmLoadBalancer -LoadBalancer $lb 
       
    if($setLB)
    {
    write-verbose "load balancer backend pool and rule created"
    }
    else
    {
    Throw "Failed to create new load balancer backend pool $AddBackendPoolName and rule"
    }
    
    foreach($VMName in $AddBackendPoolVMName)
    {
    #get vm netword interface
    $vm1= get-azurermvm |where{$_.Name -eq $VMName}
    $VMvnic = ($vm1.NetworkProfile.NetworkInterfaces.id).split("/")
    $VMvnicName= $VMvnic[($VMvnic.Length -1)]

    #add network interface to lb
    $lb = Get-AzureRmLoadBalancer –name $LBName -resourcegroupname $VirtualMachineResourceGroupName 
    $backend = Get-AzureRmLoadBalancerBackendAddressPoolConfig -name $AddBackendPoolName -LoadBalancer $lb
    $nic = Get-AzureRmNetworkInterface -Name $VMvnicName -ResourceGroupName $($vm1.ResourceGroupName)
    $count = $nic.IpConfigurations[0].LoadBalancerBackendAddressPools.Count
    if ($count -gt 0)
    {
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools+=$backend
    }
    elseif ($count -eq 0)
    {
    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools=$backend
    }

    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
    if($setnic)
    {
    write-verbose "Updated Nic for vm $VMName"
    }
    else
    {
    throw "Update NIC: unable to update NIC for  ${$VMName} "
    }
    }
    #final result    
    $status = "SUCCESS"
    $returnMessage = "Load Balancer Backend pool: $AddBackendPoolName created successfully."
    }
    #endregion   
} 
catch 
{
    $status = "FAILURE"
	$returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage
Write-Output $statuslbprobename
Write-Output $statuslbrulename