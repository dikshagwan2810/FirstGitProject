param
(
    [Parameter(Mandatory=$true)] 
    [String] 
    $SubscriptionId
)


try
{
	#First login with the default connection
	$Conn = Get-AutomationConnection -Name DefaultRunAsConnection
	$AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
	-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
  
	Write-Output "Default login ok!"

	# Find the automation account or resource group of this Job
	Write-Output ("Finding the ResourceGroup and AutomationAccount this job is running in ...")

	$RunbookJobId = $PSPrivateMetadata.JobId.Guid
	$RunbookResourceGroupName = ""
	$AutomationAccountName = ""

	if ([string]::IsNullOrEmpty($RunbookJobId))
	{
			throw "This is not running from the automation service. Please specify ResourceGroupName and AutomationAccountName as parameters"
	}
	$AutomationResource = Find-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts
	foreach ($Automation in $AutomationResource)
	{

		$Job = Get-AzureRmAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $RunbookJobId -ErrorAction SilentlyContinue
		if (!([string]::IsNullOrEmpty($Job)))
		{
				$RunbookResourceGroupName = $Job.ResourceGroupName
				$AutomationAccountName = $Job.AutomationAccountName
				break;
		}
	}

	Write-Output "This is what we found for the Id of the job currently running:"
	Write-Output $RunbookResourceGroupName
	Write-Output $AutomationAccountName

    $JsonString = Get-AzureRmAutomationVariable -ResourceGroupName $RunbookResourceGroupName -AutomationAccountName $AutomationAccountName -Name "MPCAConfiguration"
    Write-Output $JsonString
    $Configuration = $JsonString.Value | ConvertFrom-Json

    Write-Output $Configuration.MPCAConfiguration.NamingStandard.SectionA
    Write-Output $Configuration.MPCAConfiguration.NamingStandard.SectionB
    ForEach ($Subscription in $Configuration.MPCAConfiguration.Subscriptions) 
    {
        Write-Output $Subscription.Name
        Write-Output $Subscription.Id
    }

	#Then determine with information stored in the default connection which RunAsConnection (= subscription) should be used.
	$connections = Invoke-Expression (Get-AzureRmAutomationVariable -ResourceGroupName $RunbookResourceGroupName -AutomationAccountName $AutomationAccountName -Name "RunAsConnectionRepository").Value
	$connectionname = $connections.Item($SubscriptionId)
	if (([string]::IsNullOrEmpty($connectionname))) 
	{
		throw ("SubscriptionId: " + $SubscriptionId + " not found in RunAsConnectionRepository.")
	}

	$Conn = Get-AutomationConnection -Name $connectionname

	$AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
	-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

    if ($AddAccount -eq $null)
    {
        throw "Context switch: Azure logon failed"
    }
    else
    {
        Write-Output "Logged on to Azure: " $AddAccount
    }

	# Select the correct subscription there could be multiple 
	$AzureContext = Select-AzureRmSubscription -SubscriptionId $SubscriptionId
    if ($AzureContext -eq $null)
    {
        throw "Context switch: subscription failed"
    }
    else
    {
        $subscriptionname = $AzureContext.Subscription.SubscriptionName
        Write-Output "Switched to customer subscription: " $subscriptionname
    }

	#Get all ARM resources from all resource groups
	$ResourceGroups = Get-AzureRmResourceGroup 

	foreach ($ResourceGroup in $ResourceGroups)
	{    
		Write-Output ("Showing resources in resource group " + $ResourceGroup.ResourceGroupName)
		$Resources = Find-AzureRmResource -ResourceGroupNameContains $ResourceGroup.ResourceGroupName | Select ResourceName, ResourceType
		ForEach ($Resource in $Resources)
		{
			Write-Output ($Resource.ResourceName + " of type " +  $Resource.ResourceType)
		}
		Write-Output ("")
	} 

	Write-Output "Done!"
}
catch
{
    $ErrorState = 1
	$ErrorMessage = "$_" 
    $resultcode = "FAILURE"

	Write-Output -InputObject $ErrorMessage 
}