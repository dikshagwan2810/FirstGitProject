# New-ResourceGroup

This runbook deploys a standard resource group and associated objects.

## Runbook overview and deployed resources

This runbook deploys a new Resource Group into the specified Azure subscription and location.  The full name for the resource group is created using the supplied suffix as well as standard elements from the customer's environment as per the Atos Azure naming convention.

Once the resource group itself is created, the runbook will then create a Storage Account in the new resource group.

A Recovery Vault for the group is also created. The vault is created in the `<customerCode>-rsg-recoveryvaults` resource group, not in the new resource group.


## Prerequisites

* `Microsoft.RecoveryServices` subscription provider registration
* `AzureRm.RecoveryServices` module
* `AzureRm.RecoveryServices.Backup` module


## Usage

### Runbook Parameters

| Parameter | Type | Example | Notes |
|---|---|---|---|
|`SubscriptionID` | [string] | 692b17bd-3d27-4da0-bd12-40aa55e8c8b3 | The ID of the subscription where the resource group is to be deployed. |
| `ResourceGroupName` | [string] | MyWebApp | The suffix for the resource group |
| `ResourceGroupLocation` | [string] | West Europe | The Azure location when the resource group will be deployed |
| `EnvironmentType` | [string] | Development | One of: Development, Production |
|`SnowUserAccount` | [string] | a601181 | The user account of the SNOW user |
|`SnowCiID` | [string] | a601181 | The CiID for the SNOW connection |
