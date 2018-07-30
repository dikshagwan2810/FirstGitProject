#Requires -Modules Atos.RunbookAutomation
<#
  .SYNOPSIS
    Script to add new resource group.
  
  .DESCRIPTION
    Script to add new resource group.
    The script handles multiple subscriptions.
    The script deploys the resource group in development as well as production environment.
    The script also created an associated recovery vault
  
  .NOTES
    Author:     Peter Lemmen, Ankita Chaudhari, Rashmi Kanekar, Russ Pitcher
    Company:    Atos
    Email:      peter.lemmen@atos.net & ankita.chaudhari@atos.net
    Created:    2016-12-01
    Updated:    2017-04-12
    Version:    1.1
   
   .Note 
        Enable the Log verbose records of runbook 
        1.1 Refactored to sue module and harmonise parameters
#>
Param
(
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)] 
    [String] 
    $SubscriptionId,

    # The name of the Resource Group to create
    [Parameter(Mandatory=$true)] 
    [String] 
    $ResourceGroupName,

    # The location to create the Resource Group in
    [Parameter(Mandatory=$true)] 
    [String] 
    $ResourceGroupLocation,

    # The type of Resource Group.  i.e. Development/Production
    [Parameter(Mandatory=$true)] 
    [String] 
    $EnvironmentType,

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
    if ([string]::IsNullOrEmpty($ResourceGroupLocation)) {throw "Input parameter: ResourceGroupLocation missing."}
    if ([string]::IsNullOrEmpty($EnvironmentType)) {throw "Input parameter: EnvironmentType missing."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}
	if ([string]::IsNullOrEmpty($ResourceGroupName)) {throw "Input parameter: ResourceGroupName missing."}
    if ($ResourceGroupName.length -gt 48) {throw "Input parameter: ResourceGroupName accepts a maximum of 48 characters"}

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections | Out-Null

    Write-Verbose "Generate Resource Group name prefix"
    $EnvironmentConfiguration = $Runbook.Configuration.Environments | Where-Object {$_.Name -eq $EnvironmentType}
    if ($EnvironmentConfiguration -eq $null) {
        throw "EnvironmentType: ${EnvironmentType} is invalid."
    }

    Write-Verbose "Build resource group name"
    $PrefixSectionA = $Runbook.Configuration.Customer.NamingConventionSectionA
    $PrefixSectionB = ($Runbook.Configuration.Subscriptions | Where-Object {$_.Id -eq $SubscriptionId}).NamingConventionSectionB
    $PrefixSectionC = ($EnvironmentConfiguration | Where-Object {$_.Name -eq $EnvironmentType}).NamingConventionSectionC
    $ResourceGroupNamePrefix = ("${PrefixSectionA}-${PrefixSectionB}-${PrefixSectionC}-rsg").ToLower()
    if ($ResourceGroupNamePrefix -notmatch '^[a-z0-9]{3}-[a-z0-9]{4}-[d|p]-rsg$') {
        $ErrorMessage = "Resource group prefix is invalid!"
        if ($PrefixSectionA.ToLower() -notMatch '^[a-z0-9]{3}$') {$ErrorMessage += ", NamingConventionSectionA '${PrefixSectionA}' is incorrect"}
        if ($PrefixSectionB.ToLower() -notMatch '^[a-z0-9]{4}$') {$ErrorMessage += ", NamingConventionSectionB '${PrefixSectionB}' is incorrect"}
        if ($PrefixSectionC.ToLower() -notMatch '^[d|p]$') {$ErrorMessage += ", NamingConventionSectionC '${PrefixSectionC}' is incorrect"}
        throw $ErrorMessage
    }
    $StorageAccountTemplate = $EnvironmentConfiguration.StorageAccountsTemplate
    
    Write-Verbose "ResourceGroupNamePrefix is ${ResourceGroupNamePrefix}"
	Write-Verbose "ResourceGroupName is ${ResourceGroupName}"
    Write-Verbose "ResourceGroupLocation is ${ResourceGroupLocation}"
    Write-Verbose "EnvironmentType is ${EnvironmentType}"
    Write-Verbose "RunbookResourceGroupName is $($Runbook.ResourceGroup)"

	#Validation of Resource Group Name
	if ($ResourceGroupName -match "^[a-zA-Z0-9]+$") {
		Write-Verbose "Acceptable Resource Group name"
	} else {
		throw "ResourceGroupName: ${ResourceGroupName} contains an invalid character."
	}
	#End of Validation of Resource Group Name

	#Validation of location
	$LocationCheck = Get-AzureRmLocation | Where-Object { $_.DisplayName -eq $ResourceGroupLocation }
	if ($LocationCheck -eq $null) {
		throw "ResourceGroupLocation: ${ResourceGroupLocation} not found."
	}
	Write-Verbose "Location is OK!"
	#End of location validation

	Write-Verbose "All input is OK!"

	#Creating Resource Group in Environment type Specified
    Write-Verbose "Environment type: ${EnvironmentType}"
	$FullResourceGroupName = ("${ResourceGroupNamePrefix}-${ResourceGroupName}").ToLower()
	if ((Get-AzureRmResourceGroup -Name $FullResourceGroupName -ErrorAction SilentlyContinue) -ne $null) {
        throw "ResourceGroupName: ${FullResourceGroupName} already exists."
    }

	New-AzureRmResourceGroup -Name $FullResourceGroupName -Location $ResourceGroupLocation -Verbose -Force | Out-Null
		
	$params = @{StorageAccountName=$ResourceGroupName;}
	$armSnippetUrl = "https://$($Runbook.StorageAccount).blob.core.windows.net/armtemplates/${StorageAccountTemplate}"
    
	Write-Verbose "Template deployment check for URI: ${armSnippetUrl}"
	$TemplateCheckOp = Test-AzureRmResourceGroupDeployment -ResourceGroupName $FullResourceGroupName -TemplateUri $armSnippetUrl -TemplateParameterObject $params  
	if ($TemplateCheckOp -ne $null) {
		throw "$($TemplateCheckOp.Message)"
	}

	Write-Verbose "Creating Storage account..."
    $DeploymentName = "Deploy${EnvironmentType}StorageAccount-$(((Get-Date).ToUniversalTime()).ToString('yyyyMMdd-HHmm'))"
	New-AzureRmResourceGroupDeployment -Name $DeploymentName `
                                        -ResourceGroupName $FullResourceGroupName `
                                        -TemplateUri $armSnippetUrl `
                                        -TemplateParameterObject $params `
                                        -Force -Verbose `
                                        -Mode Complete `
                                        -ErrorVariable ErrorMessages | Out-Null
      
	# End of Creating Resource Group in Development Environment and Production Environment type
	$status = "SUCCESS"
    $returnMessage = "ResourceGroup: ${FullResourceGroupName} created successfully."
} catch {
    $status = "FAILURE"
	$returnMessage = $_.ToString() 
}

Write-Output $status
Write-Output $returnMessage
