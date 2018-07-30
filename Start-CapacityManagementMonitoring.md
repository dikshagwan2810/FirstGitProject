CapacityManagementMonitoring.ps1
===================
This runbooks perform capacity management monitoring for Azure, it sends alerts to ServiceNow portal when a threshold or limit is reached
for some specific Azure resouces items.
The Powershell Script is a standalone runbook, intended to be ran on a regular basis in the management subscription.

- Calculate usage and limits for a predifined list of items in Azure for capacity monitoring
- Send alerts to ServiceNow portal using webhook call to create incident when a threshold is reached or limit is reached

The runbook relies on the customer configuration JSON variable to obtain
customer subscription informations and monitoring items data and thresholds.

**Script Execution**
	
The script will get the monitoring items configuration for the specific customer from the MPCAConfiguration variable,
under the "monitoring" section. Example of configuration :


    "Monitoring": {
      "CapacityManagement": {
        "SNOWWebhookURI": "https://atosglobaldev.service-now.com/oms.do",
        "Items": [
          {
            "ItemShortName": "vm_count",
            "ItemDisplayName": "VMs per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "vm_cores",
            "ItemDisplayName": "VMs Total Cores per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "as_count",
            "ItemDisplayName": "Availability Sets per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "sa_count",
            "ItemDisplayName": "Storage accounts per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "rg_count",
            "ItemDisplayName": "Resource Groups per subscription",
            "Limit": 800,
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "vm_per_sa",
            "ItemDisplayName": "VMs per storage account",
            "Limit": 50,
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "vn_count",
            "ItemDisplayName": "Virtual networks per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "nic_count",
            "ItemDisplayName": "Network Interfaces per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "privip_per_vn",
            "ItemDisplayName": "Private IP Addresses per virtual network",
            "Limit": 4096,
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "nsg_count",
            "ItemDisplayName": "Network Security Groups per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "pubip_dyn_count",
            "ItemDisplayName": "Dynamic Public IP addresses per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "pubip_stat_count",
            "ItemDisplayName": "Static Public IP addresses per region per subscription",
            "AlertThresholdPercent": 80
          },
          {
            "ItemShortName": "lb_count",
            "ItemDisplayName": "Load balancers per region per subscription",
            "AlertThresholdPercent": 80
          }
        ]
      }
    }

The script will connect to each customer's subscription using SPN, and will collect information for implemented items
using the appropriate cmd-lets to retrieve Azure usage and configured-limits for this resource.
Some items limit are subscription wide, some are limited to a location.

For each Subscription, the script will retrieve subscription-wide (global) limits, then will loop through each customer's location 
and will retrieve usage and limit for the implemented items.

For each processed item, the script will check if the value is over the threshold for that item, and will generate an alert if true.
When an alert is to be sent, the JSON payload is built with usefull information and sent to the ServiceNow portal webhook to create the event in Evanios/ATF.
The Alert name and severity will be different depending on the case :

-	A warning alert is sent when the count is over the threshold percent value
	(For example if the limit for the subscription is 1000 VM and the threshold is 80%,
	A warning alert will be sent if there is more than 800 VMs)
-	A critical alert is sent if the limit has been reached for an item.


Currently the item monitored are :
- VMs per region per subscription								Per Region Per Subscription
- VMs Total Cores per region per subscription					Per Region Per Subscription
- Storage accounts per subscription								Per Subscription
- Availability Sets per region per subscription					Per Region Per Subscription
- VMs per storage account										Per Storage account
- Resource Groups per subscription								Per Subscription
- Virtual networks per region per subscription					Per Region Per Subscription
- Network Interfaces per region per subscription				Per Region Per Subscription
- Private IP Addresses per virtual network						Per Region Per Subscription
- Network Security Groups per region per subscription			Per Region Per Subscription
- Dynamic Public IP addresses per region per subscription		Per Region Per Subscription
- Static Public IP addresses per region per subscription		Per Region Per Subscription
- Load balancers per region per subscription					Per Region Per Subscription


Notes
-------------------
The runbook will be enhanced in future versions to process more items, but for some of them no cmd-lets are available 
so the value and limit will be retrieved through the Azure REST API.
Also, the runbook may generate CSV files in storage accounts for repoting purpose with PowerBI.
