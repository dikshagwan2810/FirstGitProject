#Requires -Modules Atos.RunbookAutomation, Atos.AlertingEvaniosIntegration

<#
.SYNOPSIS
    This runbooks perform capacity management monitoring for Azure, it sends alerts to ServiceNow portal when a threshold or limit is reached.
    
.DESCRIPTION
    - Calculate usage and limits for a predefined list of items in Azure for capacity monitoring
    - Send alerts to ServiceNow portal using webhook call to create incident when a threshold is reached or limit is reached

    The runbook relies on the customer configuration JSON variable to obtain
    customer subscription information and monitoring items data and thresholds.

.INPUTS
    - String

.OUTPUTS
    Progress logging
        
.NOTES
    FUNCTION LISTING

        ProcessItemData
            This function is called each time an item is evaluated/calculated in the main script.
            The item count and threshold is calculated and an alert in ServiceNow portal is generated if necessary,
            and progress information is displayed.

        GenerateAlertData
            This function is called to generate the alert data that will be sent to ServiceNow portal.
            The severity of alert is "warning" when the item count is over threshold value, and "critical" when the limit is reached.

    Author:     Frederic TRAPET
    Company:    Atos
    Email:      frederic.trapet@atos.net
    Created:    2017-04-20
    Updated:    2017-11-22
    Version:    1.8

.Notes 
    - This runbook must be scheduled within a Azure Automation account in the Management subscription to run every 6 hours
#>

###
### CONSTANTS
###

# Other string definitions
[string] $SNOWAlertCategoryName = "AZURE CAPACITY MONITORING"
[string] $SNOWAlertNamePrefixWarning = "Limit almost reached for"
[string] $SNOWAlertNamePrefixCritical = "Limit reached for"


### 
### LOCAL FUNCTIONS
###

#region Functions

Function ProcessItemData {
    param(
        [Parameter(Mandatory=$true)]
        [String] $ItemShortName,

        [Parameter(Mandatory=$true)]
        [PSCustomObject] $CustomerSubscription,

        [Parameter(Mandatory=$false)]
        [PSCustomObject] $CustomerLocation,
    
        [Parameter(Mandatory=$true)]
        [int] $ItemCount,
        
        [Parameter(Mandatory=$false)]
        [String] $ItemCountLimit,

        [Parameter(Mandatory=$false)]
        [String] $InstanceName,

        [Parameter(Mandatory=$true)]
        [String] $AlertItemName
    )

    # Define the location name
    $LocationDisplayName = $CustomerLocation.DisplayName
    If (!$LocationDisplayName) {$LocationDisplayName = "Global"}

    # Get configuration for item from customer's JSON
    If ($ItemsConfigJSON[$ItemShortName]) {
        # If no limit is specified in JSON, then use dynamic limit from Azure if available
        If ($NULL -ne $ItemsConfigJSON[$ItemShortName].Limit ) {$ItemCountLimit = $ItemsConfigJSON[$ItemShortName].Limit}
        # If a limit is found, process item
        If ($NULL -ne $ItemCountLimit) {

            # Calculate the threshold value based on the percentage for alert
            $ThresholdValue = [int](([int]$ItemsConfigJSON[$ItemShortName].AlertThresholdPercent / 100) * [int]$ItemCountLimit)

            # Display progress information
            $itemdisplayname = $ItemsConfigJSON[$ItemShortName].ItemDisplayName
            If ($InstanceName) {$itemdisplayname+=" ("+$InstanceName+")"}            
            write-verbose -Message ("Processing item ["+$itemdisplayname+"] Location ["+$LocationDisplayName +"] Count ["+$ItemCount+"/"+$ItemCountLimit+"] Threshold ["+$ItemsConfigJSON[$ItemShortName].AlertThresholdPercent+"%]") 
            write-output ("Processing item ["+$itemdisplayname+"] Location ["+$LocationDisplayName +"] Count ["+$ItemCount+"/"+$ItemCountLimit+"] Threshold ["+$ItemsConfigJSON[$ItemShortName].AlertThresholdPercent+"%]") 

            # If value is over threshold (or equal), then generate an alert in ServiceNow
            If ($ItemCount -ge $ThresholdValue) {
                # Generate the alert data based on threshold value and other item information
                $params = @{
                    ItemShortName = $ItemShortName
                    CustomerSubscription = $CustomerSubscription
                    CustomerLocation = $CustomerLocation
                    ItemCount = $ItemCount
                    ItemCountLimit = $ItemCountLimit
                    ThresholdPercent = $ItemsConfigJSON[$ItemShortName].AlertThresholdPercent
                    ThresholdValue = $ThresholdValue
                    AlertItemName = $AlertItemName
                    InstanceName = $InstanceName
                }
                $AlertData = GenerateAlertData @params
                
                # Generate the alert array object that will be used for JSON payload 
                $params = @{
                    AlertRuleName = $AlertData.AlertRuleName
                    OMSWorkspaceID = $OMSWorkspace.CustomerID
                    SeverityNumber = $AlertData.Severity
                    RowData = $AlertData.Rowdata
                }
                $AlertDataObj = Get-MPCAEvaniosAlertArrayObject @params
                
                # Finally, send the alert to the Webhook in Evanios/ServiceNow
                $params = @{
                    AlertDataObj = $AlertDataObj
                    WebhookURI = $Runbook.Configuration.Monitoring.CapacityManagement.SNOWWebhookURI
                }
                Send-MPCAEvaniosAlert @params    
                
                write-verbose -Message ("Alert sent to SNOW with Alert-name ["+$AlertData.AlertRuleName+"]") 
                write-output ("Alert sent to SNOW with Alert-name ["+$AlertData.AlertRuleName+"]") 
            }
        } else {
            Write-Warning -Message ("Unable to find a static or dynamic limit for item ["+$ItemShortName+"]")
        }
    } else {
        # Error : No Configuration found for this item !
        Write-Warning -Message  ("Unable to find a configuration entry for item ["+$ItemShortName+"]")
    }
}

# This function is called to generate alert data content based on monitored item
Function GenerateAlertData {
    param(
        [Parameter(Mandatory=$true)]
        [String] $ItemShortName,

        [Parameter(Mandatory=$true)]
        [PSCustomObject] $CustomerSubscription,

        [Parameter(Mandatory=$false)]
        [PSCustomObject] $CustomerLocation,
    
        [Parameter(Mandatory=$true)]
        [Int] $ItemCount,

        [Parameter(Mandatory=$true)]
        [Int] $ItemCountLimit,

        [Parameter(Mandatory=$true)]
        [String] $ThresholdPercent,

        [Parameter(Mandatory=$true)]
        [int] $ThresholdValue,

        [Parameter(Mandatory=$false)]
        [String] $InstanceName,

        [Parameter(Mandatory=$true)]
        [String] $AlertItemName
    )

    # Define the location name
    $LocationDisplayName = $CustomerLocation.DisplayName
    If (!$LocationDisplayName) {$LocationDisplayName = "Global"}
    
    # Prepare the text for the Alert Name and description
    If ($ItemCount -lt $ItemCountLimit) {
        $alert_name = $SNOWAlertNamePrefixWarning+" "+$AlertItemName.ToUpper()
        $alert_severity = "2"
    } else {
        $alert_name = $SNOWAlertNamePrefixCritical+" "+$AlertItemName.ToUpper()
        $alert_severity = "1"
    }

    # Append unique information to the alert name to avoid de-duplication on ServiceNow side
    If (!$InstanceName) {    
        $alert_name += " ["+$CustomerSubscription.Name+"/"+$LocationDisplayName+"]"
    } else {
        $alert_name += " ["+$InstanceName+"] - "
    }

    # Generate the alert data array
    $AlertData = @{
        "AlertRuleName" = $alert_name;
        "Severity" = $alert_severity
        "Rowdata" = (New-Object System.Collections.ArrayList)
    }
    If ($InstanceName) {    
        $AlertData.Rowdata.Add(@{"Object name"=$InstanceName}) | out-null
    }
    $AlertData.Rowdata.Add(@{"Actual count"=$ItemCount}) | out-null
    $AlertData.Rowdata.Add(@{"Actual limit"=$ItemCountLimit}) | out-null
    $AlertData.Rowdata.Add(@{"Alert threshold"=$ThresholdPercent+" %"}) | out-null
    $AlertData.Rowdata.Add(@{"Customer subscription name"=$CustomerSubscription.Name}) | out-null
    $AlertData.Rowdata.Add(@{"Customer subscription ID"=$CustomerSubscription.ID}) | out-null
    $AlertData.Rowdata.Add(@{"Customer location"=$LocationDisplayName}) | out-null
    $AlertData.Rowdata.Add(@{"Customer code"=$Runbook.Configuration.Customer.NamingConventionSectionA.ToUpper()}) | out-null
    return $AlertData
}

#endregion

###
### SCRIPT START
###

# Connect to the management subscription
Write-Verbose "Connect to default subscription"
Connect-AtosManagementSubscription | Out-Null

Write-Verbose "Retrieve runbook objects"
# Set the $Runbook object to global scope so it's available to all functions
$global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

# Read capacity-monitoring data from configuration JSON
$ItemsConfigJSON = @{}
ForEach ($item in  $Runbook.Configuration.Monitoring.CapacityManagement.Items) {
    $ItemsConfigJSON+= @{$item.ItemShortName=$item}
}

# Loop through all customer subscriptions
ForEach ($Subscription in $Runbook.Configuration.Subscriptions) {
    
    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    Connect-AtosCustomerSubscription -SubscriptionId $Subscription.Id -Connections $Runbook.Connections | Out-Null
    write-output ("Authenticated on subscription ["+$Subscription.Name+"]")

    # Get a list of used Azure locations for this subscription, based of VNET presence
    $AzureLocations = Find-AzureRmResource -ResourceType "Microsoft.Network/virtualNetworks" | Group-Object Location | Select-Object Name
    
    # Get the OMS workspace ID for this subscription (needed by SNOW)
    $OMSWorkspace = Get-AzureRmOperationalInsightsWorkspace -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $Subscription.OMSWorkspaceName}
    If (!$OMSWorkspace) {
        throw ("Can't find the OMS workspace ID for the workspace name ["+$Subscription.OMSWorkspaceName+"]")        
    }
    
    write-verbose -Message ("Using OMS Workspace ["+$Subscription.OMSWorkspaceName+"] ID ["+$OMSWorkspace.CustomerID+"]")
    write-output ("Using OMS Workspace ["+$Subscription.OMSWorkspaceName+"] ID ["+$OMSWorkspace.CustomerID+"]")
    write-verbose -Message ("Using SNOW Webhook URI ["+$Runbook.Configuration.Monitoring.CapacityManagement.SNOWWebhookURI+"]")
    write-output ("Using SNOW Webhook URI ["+$Runbook.Configuration.Monitoring.CapacityManagement.SNOWWebhookURI+"]")

    ###
    ### Get Storage-accounts usage (all locations)
    ###

    $SACCUsage = Get-AzureRmStorageUsage
    If ($SACCUsage) {      
        $params = @{
            ItemShortName = "sa_count"
            CustomerSubscription = $Subscription 
            ItemCount = $SACCUsage.CurrentValue 
            ItemCountLimit = $SACCUsage.Limit
            AlertItemName = "NUMBER OF STORAGE ACCOUNTS"
        }
        ProcessItemData @params
    } else {
        Write-Warning -Message ("Unable to get usage information for item [SA_COUNT]")
    }        

    ###
    ### Get Resource-groups usage (all locations)
    ###

    $RGList = Get-azurermresourcegroup
    If ($RGList) {
        $params = @{
            ItemShortName = "rg_count"
            CustomerSubscription = $Subscription 
            ItemCount = $RGList.count 
            AlertItemName = "NUMBER OF RESOURCE GROUPS"
        }
        ProcessItemData @params
    } else {
        Write-Warning -Message ("Unable to get usage information for item [RG_COUNT]")
    }   

    # Loop through all customer locations within this subscription
    ForEach ($AzureLocation in $AzureLocations) {
        $Location = Get-AzureRmLocation -ErrorAction SilentlyContinue | Where-Object {$_.Location -eq $AzureLocation.Name}
        If (!$Location) {
            Write-Warning -Message ("Unable to find Azure location for location name ["+$AzureLocation.Name+"]")
            break
        }

        ###
        ### Get VM, Cores and Availability-sets usage
        ###

        $VMUsage = Get-AzureRmVMUsage -ErrorAction SilentlyContinue -Location $Location.Location

        $TotalVM = $VMUsage | Where-Object {$_.Name.Value -eq "virtualMachines"}
        If ($TotalVM) {
            # Process VM count for this region
            $params = @{
                ItemShortName = "vm_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $TotalVM.CurrentValue
                ItemCountLimit =  $TotalVM.Limit
                AlertItemName = "NUMBER OF VM"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [VM_COUNT] Location ["+$Location.Location+"]")
        }

        # Process VM cores count for this region
        $TotalVMCores = $VMUsage | Where-Object {$_.Name.Value -eq "cores"}
        If ($TotalVMCores) {        
            $params = @{
                ItemShortName = "vm_cores"
                CustomerSubscription = $Subscription
                CustomerLocation = $Location
                ItemCount = $TotalVMCores.CurrentValue
                ItemCountLimit = $TotalVMCores.Limit
                AlertItemName = "NUMBER OF VM CORES"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [VM_CORES] Location ["+$Location.Location+"]")
        }

        # Process Availibility-sets count for this region
        $TotalVMAvail = $VMUsage | Where-Object {$_.Name.Value -eq "availabilitySets"}
        If ($TotalVMAvail) {         
            $params = @{
                ItemShortName = "as_count"
                CustomerSubscription = $Subscription
                CustomerLocation = $Location
                ItemCount = $TotalVMAvail.CurrentValue
                ItemCountLimit = $TotalVMAvail.Limit
                AlertItemName = "NUMBER OF AVAILABILITY-SETS"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [AS_COUNT] Location ["+$Location.Location+"]")
        }

        ###
        ### Get Network items usage
        ###

        $NetUsage = Get-AzureRmNetworkUsage -ErrorAction SilentlyContinue -Location $Location.Location

        # Process Virtual Networks count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Virtual Networks"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "vn_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF VIRTUAL NETWORKS"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [VN_COUNT] Location ["+$Location.Location+"]")
        }

        # Process Network Interfaces count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Network Interfaces"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "nic_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF NETWORK INTERFACES"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [NIC_COUNT] Location ["+$Location.Location+"]")
        }

        # Process Network Security Groups count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Network Security Groups"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "nsg_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF NET SECURITY GROUPS"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [NSG_COUNT] Location ["+$Location.Location+"]")
        }

        # Process Public IP addresses count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Public IP Addresses"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "pubip_dyn_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF DYNAMIC PUBLIC IP"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [PUBIP_DYN_COUNT] Location ["+$Location.Location+"]")
        }

        # Process Static Public IP addresses count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Static Public IP Addresses"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "pubip_stat_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF STATIC PUBLIC IP"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [PUBIP_STAT_COUNT] Location ["+$Location.Location+"]")
        }

        # Process Load Balancers count for this region
        $virtualNetworksUsage = $NetUsage | Where-Object {$_.ResourceType -eq "Load Balancers"}
        If ($virtualNetworksUsage) {
            $params = @{
                ItemShortName = "lb_count"
                CustomerSubscription =  $Subscription
                CustomerLocation =  $Location
                ItemCount =  $virtualNetworksUsage.CurrentValue
                ItemCountLimit =  $virtualNetworksUsage.Limit
                AlertItemName = "NUMBER OF LOAD BALANCERS"
            }
            ProcessItemData @params
        } else {
            Write-Warning -Message ("Unable to get usage information for item [LB_COUNT] Location ["+$Location.Location+"]")
        }

        ###
        ### Count the number of Private IP per Virtual Network
        ###

        Try {
            $vnetList = Get-AzureRmVirtualNetworK -ErrorAction stop -WarningAction SilentlyContinue | Where-Object {$_.Location -eq $Location.Location}
            ForEach ($vnet in $vnetList) {
                $PrivateIPCount = 0
                ForEach ($subnet in $vnet.subnets) {
                    $PrivateIPCount += $subnet.IpConfigurations.Count
                }
                $params = @{
                    ItemShortName = "privip_per_vn"
                    CustomerSubscription = $Subscription
                    CustomerLocation = $Location
                    ItemCount = $PrivateIPCount
                    InstanceName = $vnet.Name
                    AlertItemName = "NUMBER OF PRIVATE IP IN VNET"
                }
                ProcessItemData @params                
            }
        } catch {
            Write-Warning -Message ("Unable to get usage information for item [PRIVIP_PER_VN] Location ["+$Location.Location+"]")
        }

        ###
        ### Count the number of VMs VHD per storage account for this region
        ###

        # Build an array with count
        Try {
            $VMList = Get-AzureRMVM -ErrorAction stop -WarningAction SilentlyContinue | Where-Object {$_.Location -eq $Location.Location}
            If ($VMList) { 
                $StorageAccounts_VMcount = @{}
                ForEach ($vm in $VMList) {
                    $os_vhd = $vm.StorageProfile.OsDisk.Vhd.Uri
                    If ($os_vhd) {
                        $os_vhd = $os_vhd.split(".")[0].replace("https://","").replace("http://","")
                        $StorageAccounts_VMcount[$os_vhd]++
                    }
                }
                # Loop through array and process each items
                ForEach ($item in $StorageAccounts_VMcount.GetEnumerator()) {
                    $params = @{
                        ItemShortName = "vm_per_sa"
                        CustomerSubscription = $Subscription
                        CustomerLocation = $Location
                        ItemCount = $item.Value
                        InstanceName = $item.Name
                        AlertItemName = "NUMBER OF VM IN STORAGE ACCOUNT"
                    }
                    ProcessItemData @params
                }
            }
        } catch {
            Write-Warning -Message ("Unable to get usage information for item [VM_PER_SA] Location ["+$Location.Location+"]")
        }
    }
}
