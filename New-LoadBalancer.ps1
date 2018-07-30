#Requires -Modules Atos.RunbookAutomation 
<#
    .SYNOPSIS
    This script creates New Load balancer.
   
    .DESCRIPTION
    - Create internal load balancer 
    - create backend pool and add vm to the LB
    - create frontend pool and  to get ip from Vnet and subnet specified by user
    - create load balancing rules

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

    [Parameter(Mandatory=$true)]
    [String]
    $LBType,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineResourceGroupName,

    [Parameter(Mandatory=$True)]
    [String]
    $AvailabilitySet,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineName,

    [Parameter(Mandatory=$True)]
    [String]
    $LBName,

    [Parameter(Mandatory=$false)]
    [String]
    $LBPublicName,

    [Parameter(Mandatory=$True)]
    [String]
    $BackendPoolName,

    [Parameter(Mandatory=$false)]
    [String]
    $VirtualNetworkResourceGroupName,

    [Parameter(Mandatory=$false)]
    [String]
    $VirtualNetworkName,

    [Parameter(Mandatory=$false)]
    [String]
    $VirtualNetworkSubnetName,

    [Parameter(Mandatory=$true)]
    [int]
    $healthProbePort,

    [Parameter(Mandatory=$true)]
    [String]
    $LBRuleProtocal,

    [Parameter(Mandatory=$true)]
    [int]
    $LBRulePort,

    [Parameter(Mandatory=$true)]
    [int]
    $LBRuleBackendPort,

    [Parameter(Mandatory=$true)]
    [int]
    $IdleTimeoutInMinutes,

    [Parameter(Mandatory=$true)]
    [string]
    $SessionPersistence,

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
    if ([string]::IsNullOrEmpty($LBType)) {throw "Input parameter: LBType missing."}
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."}
    if($LBType -eq "Internal")
    {
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkName)) {throw "Input parameter: VirtualNetworkName missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkSubnetName)) {throw "Input parameter: VirtualNetworkSubnetName missing."}
    }
    else
    {
    if ([string]::IsNullOrEmpty($LBPublicName)) {throw "Input parameter: LBPublicName missing."}
    }
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter: VirtualMachineName missing."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkResourceGroupName)) {throw "Input parameter: VirtualNetworkResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($LBName)) {throw "Input parameter: LBName missing."}
    if ([string]::IsNullOrEmpty($healthProbePort)) {throw "Input parameter: healthProbePort missing."}
    if ([string]::IsNullOrEmpty($LBRuleProtocal)) {throw "Input parameter: LBRuleProtocal missing."}
    if ([string]::IsNullOrEmpty($LBRulePort)) {throw "Input parameter: LBRulePort missing."}
    if ([string]::IsNullOrEmpty($SessionPersistence)) {throw "Input parameter: SessionPersistence missing."}
    if ([string]::IsNullOrEmpty($IdleTimeoutInMinutes)) {throw "Input parameter: IdleTimeoutInMinutes missing."}
    if ([string]::IsNullOrEmpty($AvailabilitySet)) {throw "Input parameter: AvailabilitySet missing."}
    if ([string]::IsNullOrEmpty($BackendPoolName)) {throw "Input parameter: BackendPoolName missing."}
    if ([string]::IsNullOrEmpty($LBRuleBackendPort)) {throw "Input parameter: LBRuleBackendPort missing."}
    


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
    if($LBType -eq "Internal")
    {
    write-verbose "  VirtualMachineResourceGroupName : $VirtualMachineResourceGroupName"
    write-verbose "  VirtualNetworkName : $VirtualNetworkName"
    write-verbose "  VirtualNetworkSubnetName : $VirtualNetworkSubnetName"
    }
    else
    {
    write-verbose "  LBPublicName : $LBPublicName"    
    }
    write-verbose "  VirtualMachineName : $VirtualMachineName"
    write-verbose "  LBName : $LBName"
    write-verbose "  LBType : $LBType"
    write-verbose "  RequestorUserAccount : $RequestorUserAccount"
    write-verbose "  ConfigurationItemId : $ConfigurationItemId"
    write-verbose "  healthProbePort : $healthProbePort"
    write-verbose "  LBRuleProtocal : $LBRuleProtocal"
    write-verbose "  LBRulePort : $LBRulePort"
    write-verbose "  SessionPersistence : $SessionPersistence"
    write-verbose "  IdleTimeoutInMinutes : $IdleTimeoutInMinutes"
    write-verbose "  AvailabilitySet : $AvailabilitySet"
    write-verbose "  BackendPoolName : $BackendPoolName"
    write-verbose "  LBRuleBackendPort : $LBRuleBackendPort"
    
    #endregion

    #region Performing VmName Check
    $rollback="no"
    [array]$VirtualMachineName = $VirtualMachineName.Split(",")
    foreach($VMName in $VirtualMachineName)
    {
    $Vm = get-azurermvm |where{$_.Name -eq $VMName}
    if (!$Vm) {
        throw "VMNames: ${$VMName} does not exist!"
    }
    }
    #endregion

    #region set resource group to deploy LB
    if($LBType -eq "public")
    {
    $VirtualMachineResourceGroupName = $Vm.ResourceGroupName
    }
    #endregion

    #region Performing Resource Group Check
    write-verbose "Performing Resource Group Check for resource group ${VirtualMachineResourceGroupName}"
    $ResourceGroupInfo = Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName
    if ($ResourceGroupInfo -eq $null) {
        throw "Resource Group Name ${VirtualMachineResourceGroupName} not found"
    }
    $ResourceGroupLocation = $ResourceGroupInfo.location
    #endregion

    #region check if AV exist and all VM part of same AV

    $av = Get-AzureRmAvailabilitySet -ResourceGroupName $Vm.ResourceGroupName |where{$_.Name -eq $AvailabilitySet}
    if($av)
    {
    foreach($VMName in $VirtualMachineName)
    {
    $VMmatched = "no"
    foreach($AVmember1 in $av.VirtualMachinesReferences)
    {
    $avvm= ($AVmember1.id).Split("/")[8]
    if($VMName -eq $avvm)
    {  $VMmatched = "yes"
    }
    }
    if($VMmatched -eq "Yes")
    {
    write-verbose "VMNames: ${$VMName} is part of Availability set  ${$AvailabilitySet} !"
    }
    }
    }
    Else
    {
    throw "VMNames: All vm's are not part of Availability set  ${$AvailabilitySet} !"
    }
    #endregion

    #region prepare LB, probe, rule names
    $LBFullNameTemp =($ResourceGroupInfo.ResourceGroupName).Split("-")
    
    $LBFullName = $LBFullNameTemp[0]+"-"+$LBFullNameTemp[1]+"-lbal-"+$LBName
    $LBFullName=$LBFullName.ToLower()
    if($LBFullName)
    {
        if ($LBFullName.Length -lt 80) {
		    write-verbose "Acceptable LB name"
	    }
        else {
		throw "LBFullName: ${LBFullName} have more than 80 character."
	    }
    }
    else {
		throw "LBFullName: ${LBFullName} is invalid."
	}

    #prepare LB rule name
    $LBFullNameRuleTemp =($ResourceGroupInfo.ResourceGroupName).Split("-")
    
    $LBFullNameRule = $LBFullNameRuleTemp[0]+"-"+$LBFullNameRuleTemp[1]+"-lbrc-"+$LBName+"-"+$BackendPoolName
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
    
	#prepare LB rule name notification
	$statusrulename = "Load Balancer Rule : ${LBFullNameRule}"

    #prepare LB frontend pool name
    $LBFEName = $LBFullName+"FePool1"
    $LBFEName=$LBFEName.ToLower()
    if ($LBFEName) 
    {
    if ($LBFEName.Length -lt 80) {
		write-verbose "Acceptable LB frontend name"
	} else {
		throw "LBFEName: ${LBFEName} have more than 80 character."
	}
    }
    else
    {
    throw "LBFEName: ${LBFEName} is invalid."
    }

    #prepare LB backend pool name
    $LBBEName = $LBFullName+"-"+$BackendPoolName
    $LBBEName=$LBBEName.ToLower()
    if ($LBBEName) 
    {
    if ($LBBEName.Length -lt 80) {
		write-verbose "Acceptable LB backend name"
	} else {
		throw "LBBEName: ${LBBEName} have more than 80 character."
	}
    }
    else
    {
    throw "LBBEName: ${LBBEName} is invalid."
    }

    #prepare LB probe pool name
    $LBPBName = $LBBEName+"-Probe1"
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
    #endregion

	#prepare notification pool name
	$statuspoolname = "Load Balancer Probe : ${LBPBName}"
	
	
    #region LB, probe, rule creation
    #check if LB already exist
    $lb = Get-AzureRmLoadBalancer –name $LBFullName -resourcegroupname $VirtualMachineResourceGroupName -ErrorAction SilentlyContinue
    if($lb)
    {
    $rollback="no"
     throw "LBFullName: ${LBFullName} already exist, Please use modify SSR to update existing load balancer."
    }
    else
    {
    write-verbose "Acceptable LB as it does not exist"
    }

    if($LBType -eq "internal")
    {
    #Get Vnet and subnet detail 
    $vnet = get-AzureRmVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $VirtualNetworkResourceGroupName -ErrorAction SilentlyContinue
    if($vnet)
    {
    write-verbose "vnet ${$VirtualNetworkName} exist"
    }
    else
    {
     throw "VirtualNetworkName: ${VirtualNetworkName} does not exist."
    }

    $Subnet = get-AzureRmVirtualNetworkSubnetConfig -Name $VirtualNetworkSubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
    if($Subnet)
    {
    write-verbose "Subnet ${$VirtualNetworkSubnetName} exist"
    }
    else
    {
     throw "VirtualNetworkSubnetName: ${VirtualNetworkSubnetName} does not exist."
    }

    $frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name $LBFEName -SubnetId $Subnet.Id
    
    }
    else
    {
        $publicIpName = $LBFullName+"-pip-1"
        $LBPublicName= $LBPublicName.ToLower()
        $publicIP = New-AzureRmPublicIpAddress -Name $publicIpName -ResourceGroupName $VirtualMachineResourceGroupName -Location $ResourceGroupLocation -AllocationMethod Static -DomainNameLabel $LBPublicName
        if($publicIP)
        {
        $FinalLBip = $publicIP.IpAddress
        $FinalLBname=$publicIP.DnsSettings.Fqdn
        $frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name $LBFEName -PublicIpAddress $publicIP
        }
        else
        {
        throw "LBFEName: unable to get public ip for  ${LBFEName} "
        }
    }
    if(!($frontendIP))
    {
        throw "LBFEName: unable to create ${LBFEName} "
    }
    else
    {
    write-verbose "LBFEName: LB frontend pool is created ${LBFEName} "
    }
    #Create Front end IP pool and backend address pool
    $beaddresspool= New-AzureRmLoadBalancerBackendAddressPoolConfig -Name $LBBEName 
    if(!($frontendIP))
    {
        throw "LBBEName: unable to create ${LBBEName} "
    }

    #Create LB rules, probe and load balancer
    $healthProbe = New-AzureRmLoadBalancerProbeConfig -Name $LBPBName -Protocol tcp -Port $healthProbePort -IntervalInSeconds 15 -ProbeCount 2
    $lbrule = New-AzureRmLoadBalancerRuleConfig -Name $LBFullNameRule -FrontendIpConfiguration $frontendIP -BackendAddressPool $beAddressPool -Probe $healthProbe -Protocol $LBRuleProtocal -FrontendPort $LBRulePort -BackendPort $LBRuleBackendPort -IdleTimeoutInMinutes $IdleTimeoutInMinutes -LoadDistribution $SessionPersistence 

    #crerate LB
    $NRPLB = New-AzureRmLoadBalancer -ResourceGroupName $VirtualMachineResourceGroupName -Name $LBFullName -Location $ResourceGroupLocation -FrontendIpConfiguration $frontendIP -LoadBalancingRule $lbrule -BackendAddressPool $beAddressPool -Probe $healthProbe
    if($NRPLB)
    {
        if($NRPLB.ProvisioningState -eq "Succeeded")
        {
        write-verbose "LBFullName: ${$LBFullName} created successfully"
        }
        else
        {
        $lb = Get-AzureRmLoadBalancer –name $LBFullName -resourcegroupname $VirtualMachineResourceGroupName 
        if($lb)
        {
        write-verbose "LBFullName: ${$LBFullName} created successfully"
        }
        else{
        $rollback="yes"
        throw "LBFullName: Failed to create LB  ${LBFullName} "
        }
        }
    }
    else
    {
    
    throw "LBFullName: Failed to create LB  ${LBFullName} "
    }
    #endregion
       
    #region Assign VM to LB
    $rollback="yes"
    foreach($VMName in $VirtualMachineName)
    {
    #get vm netword interface
    $vm1= get-azurermvm |where{$_.Name -eq $VMName}
    $VMvnic = ($vm1.NetworkProfile.NetworkInterfaces.id).split("/")
    $VMvnicName= $VMvnic[($VMvnic.Length -1)]

    #add network interface to lb
    $lb = Get-AzureRmLoadBalancer –name $LBFullName -resourcegroupname $VirtualMachineResourceGroupName 
    $backend = Get-AzureRmLoadBalancerBackendAddressPoolConfig -name $LBBEName -LoadBalancer $lb
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
    #endregion

    #region set tags
    $ExistingTags =  (Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName -ErrorAction SilentlyContinue).tags
    
    if (-not [string]::IsNullOrEmpty($ConfigurationItemId)) {
    if($ExistingTags.Keys -like "CI")
    {
    $ExistingTags.CI = "$ConfigurationItemId"
    }
    else 
    {
    $ExistingTags += @{CI="$ConfigurationItemId"}
    }
    } 
    IF (-not [string]::IsNullOrEmpty($($lb.Id)))
    {
    $result = Set-AzureRmResource -Tag $ExistingTags -ResourceId $($lb.Id) -Confirm:$false -Force 
    if($result.Properties.provisioningState -eq "Succeeded")
    {
    write-verbose "Tags: Tags updated successfully on $LBFullName"
    }
    }
    #endregion

	#region Result of Load balancer
    if($LBType -eq "Public")
    {
	$status = "SUCCESS"
    $returnMessage = "Load Balancer: $LBFullName created successfully."
    }
    else
    {
    $status = "SUCCESS"
    $returnMessage = "Load Balancer: $LBFullName created successfully."
    }
    #endregion
} 
catch 
{
    #rollback
    if($rollback -eq "yes")
    {
    write-verbose "Performing rollback"
    $lb = Get-AzureRmLoadBalancer |where{$_.name -eq $LBfullName} 
    if($lb)
    {
    $VirtualMachineResourceGroupName =$lb.ResourceGroupName
    
    #remove LB with name and RG
    Remove-AzureRmLoadBalancer -Name $LBfullName -ResourceGroupName $VirtualMachineResourceGroupName -Force |Out-Null
    if($lb.FrontendIpConfigurations.publicipaddress)
    {
    $publicipname = Get-AzureRmPublicIpAddress -ResourceGroupName $VirtualMachineResourceGroupName |where{$_.Name -like "$LBfullName*"}
    if($publicipname)
     {
     Remove-AzureRmPublicIpAddress -Name $($publicipname.name) -ResourceGroupName $VirtualMachineResourceGroupName -Force |Out-Null
     $publicIPCheck="yes"
     }
    }
    }
    }
    
    #Final Status
    $status = "FAILURE"
	$returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage
Write-Output $statuspoolname
Write-Output $statusrulename
