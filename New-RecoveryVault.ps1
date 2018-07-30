#Requires -Modules Atos.RunbookAutomation

Param (
    # The ID of the subscription to use
    [Parameter(Mandatory = $true)] 
    [String] 
    $SubscriptionId,

    # The name of the Resource Group for the vault
    [Parameter(Mandatory = $true)] 
    [String] 
    $RecoveryVaultResourceGroupName,

    # The name of the vault to create
    [Parameter(Mandatory = $true)] 
    [String] 
    $RecoveryVaultName,

    # The location of the Resource Group
    [Parameter(Mandatory = $true)] 
    [String] 
    $RecoveryVaultLocation,

    # The redundancy level of the vault
    [Parameter(Mandatory = $false)] 
    [String] 
    $RecoveryVaultRedundancy = "LocallyRedundant",

    # The account of the user who requested this operation
    [Parameter(Mandatory=$false)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$false)]
    [String]
    $ConfigurationItemId
)

$returnMessage = @()

try {
    # Validate parameters (PowerShell parameter validation is not available in Azure)
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Parameter SubscriptionId is Null or Empty"}
    if ([string]::IsNullOrEmpty($RecoveryVaultResourceGroupName)) {throw "Parameter RecoveryVaultResourceGroupName is Null or Empty"}
    if ([string]::IsNullOrEmpty($RecoveryVaultName)) {throw "Parameter RecoveryVaultName is Null or Empty"}
    if ([string]::IsNullOrEmpty($RecoveryVaultLocation)) {throw "Parameter RecoveryVaultLocation is Null or Empty"}
    if ([string]::IsNullOrEmpty($RecoveryVaultRedundancy)) {throw "Parameter RecoveryVaultRedundancy is Null or Empty"}
    $allowedRedundancies = "LocallyRedundant","GeoRedundant"
    if ($allowedRedundancies -notcontains $RecoveryVaultRedundancy) {throw "RecoveryVaultRedundancy can only be one of: $($allowedRedundancies -join ', ')"}

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

    Write-Verbose "Creating Recovery Services Vault '${RecoveryVaultName}'"
    $result = New-AzureRmRecoveryServicesVault -Name $RecoveryVaultName -ResourceGroupName $RecoveryVaultResourceGroupName -Location $RecoveryVaultLocation 
    $returnMessage += "Created backup vault '${RecoveryVaultName}' successfuly."
    
    $BackupVault = Get-AzureRmRecoveryServicesVault -Name $RecoveryVaultName
    Write-Verbose "Setting redundancy to ${RecoveryVaultRedundancy}"
    Set-AzureRmRecoveryServicesBackupProperties -Vault $BackupVault -BackupStorageRedundancy $RecoveryVaultRedundancy
    $returnMessage += "`Configured redundancy to ${RecoveryVaultRedundancy}"

    $status = "SUCCESS"
} catch {
    $status = "FAILURE"
    $returnMessage = $_.ToString()
}

Write-Output $status
Write-Output $returnMessage