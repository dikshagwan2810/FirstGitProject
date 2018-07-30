#Requires -Modules Atos.RunbookAutomation 
<#
    .SYNOPSIS
    This script creates domain joined or workgroup Virtual Machine with Managed Disk.
   
    .DESCRIPTION
    - Creates Machine with only Managed Disk
    - Creates Windows Domain Join Machine with Managed Disk.
    - Standard Storage Account should be present in the Resource Group where the Machine is deployed.
    - Generates Warning while provisioning linux Machine with domain join
    - Provides option to add machine in availability set
    - Make sure the VM is deployed in same resource group as availability set.
    - Virtual Network should be same for all the machines present in availability set.


    .INPUTS
        $VirtualMachineTemplateName - Contains the template Name
        $VirtualMachineResourceGroupName - The name of Resource Group where the VM needs to be created
        $VirtualMachineNameCode - The Name of VM service abbreviation
        $VirtualMachineOSVersion - Contains the OS version for the newly deployed VM
        $RequestorUserAccount - Contains user account name of snow user
        $ConfigurationItemId - Contains id of snow user
        $VirtualNetworkResourceGroupName - Contains Resource Group Name of virtual network
        $VirtualNetworkName - Contains Network Name to be attached to newly deployed Vm
        $VirtualMachineSize - Contains the Size of Vm to be applied for newly deployed Vm
        $LocalAdministratorUserAccount - The user specifies the user account name for machine created
        $LocalAdministratorPassword - The user specifies the password for the machine created
        $UsePremiumStorage - Contains boolean value . True states the Premium storage and False states Standard Storage
        $DomainName - Contains the name of the domain. If a workgroup machine is to be created, the value of this parameter must be "None"
        $VirtualNetworkSubnetName - Contains the subnet name of the network specified
        $HybridUseBenefit - Enable HUB Feature
        $PublicIpType - Supports IP Address type as Dynamic and Static
        $EnableBootDiagnostics  - Contains Boolean value for maintaining the boot diagnostic
        $StartVmAfterProvisioning - Contains Boolean value if set to False the VM deployed is in stopped state else in running state.
        $AvailabilitySetName - Contains the name of the availability set where the machine should be added.
        $ManagedOS - Contains Boolean value for enabling Managed OS; Custom Script Extension will be used to execute a post deployment script. 
        $CustomScript - Contains the name of the PowerShell Custom script to be executed. Must include .ps1 on the end. 
        $CustomScriptArguments - Contains the arguments to be applied to the PowerShell Custom Script. 

    .OUTPUTS
    Displays processes step by step during execution
   
    .NOTES
    Author:     Ankita Chaudhari & Rashmi Kanekar
    Company:    Atos
    Email:      rashmi.kanekar@atos.net, ankita.chaudhari@atos.net
    Created:    2016-12-12
    Updated:    2017-09-14
    Version:    1.4
   
    .Note
    Enabled Custom Script Extensions
    Enable the Log verbose records of runbook
    Updated to use module and harmonise parameters
    Creates a Virtual Machine with only Managed Disk
    Allows to create a Virtual Machine in an Avalability Set
#>

Param (
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineTemplateName,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineResourceGroupName,

    [Parameter(Mandatory=$True)]
    [String]
    $VirtualMachineNameCode,

    [Parameter(Mandatory=$True)]
    [String]
    [ValidateSet('Windows 2008-R2-SP1','Windows 2012-Datacenter','Windows 2012-R2-Datacenter','Windows 2016-Nano-Server','Windows 2016-Datacenter-with-Containers','Windows 2016-Datacenter','Red Hat Enterprise Linux#6.7','Red Hat Enterprise Linux#6.8','Red Hat Enterprise Linux#7.2','Red Hat Enterprise Linux#7.3','SUSE Linux Enterprise Server#11-SP4','SUSE Linux Enterprise Server#12-SP1','SUSE Linux Enterprise Server#12-SP2','Ubuntu Server#12.04.2-LTS','Ubuntu Server#12.04.3-LTS','Ubuntu Server#12.04.4-LTS','Ubuntu Server#12.04.5-LTS','Ubuntu Server#12.10','Ubuntu Server#14.04.0-LTS','Ubuntu Server#14.04.1-LTS','Ubuntu Server#14.04.2-LTS','Ubuntu Server#14.04.3-LTS','Ubuntu Server#14.04.4-LTS','Ubuntu Server#14.04.5-LTS','Ubuntu Server#14.10','Ubuntu Server#15.04','Ubuntu Server#15.10','Ubuntu Server#16.04-LTS','Ubuntu Server#16.04.0-LTS','Ubuntu Server#16.10')]
    $VirtualMachineOSVersion,

    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId,

    [Parameter(Mandatory=$true)]
    [String]
    $VirtualNetworkResourceGroupName,

    [Parameter(Mandatory=$true)]
    [String]
    $VirtualNetworkName,

    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineSize,

    [Parameter(Mandatory=$true)]
    [String]
    $LocalAdministratorUserAccount,

    [Parameter(Mandatory=$true)]
    [String]
    $LocalAdministratorPassword,

    [Parameter(Mandatory=$true)]
    [Boolean]
    $UsePremiumStorage,

    [Parameter(Mandatory=$true)]
    [String]
    $VirtualNetworkSubnetName,

    [Parameter(Mandatory=$true)]
    [String]
    $HybridUseBenefit,

    [Parameter(Mandatory=$true)]
    [String]
    $PublicIpType,

    [Parameter(Mandatory=$true)]
    [Boolean]
    $EnableBootDiagnostics,

    [Parameter(Mandatory=$true)]
    [Boolean]
    $StartVmAfterProvisioning,

    [Parameter(Mandatory=$true)]
    [string]
    $DomainName,

    [Parameter(Mandatory=$false)]
    [string]
    $AvailabilitySetName,

    [Parameter(Mandatory=$false)]
    [Boolean]
    $ManagedOS,

    [Parameter(Mandatory=$false)]
    [String]
    $CustomScript, 

    [Parameter(Mandatory=$false)]
    [String]
    $CustomScriptArguments
)

$VmNameCheck = $False
try {
    # Input Validation
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter: SubscriptionId missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineTemplateName)) {throw "Input parameter: VirtualMachineTemplateName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter: VirtualMachineResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineNameCode)) {throw "Input parameter: VirtualMachineNameCode missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineOSVersion)) {throw "Input parameter: VirtualMachineOSVersion missing."}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter: RequestorUserAccount missing."}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter: ConfigurationItemId missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkResourceGroupName)) {throw "Input parameter: VirtualNetworkResourceGroupName missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkName)) {throw "Input parameter: VirtualNetworkName missing."}
    if ([string]::IsNullOrEmpty($VirtualMachineSize)) {throw "Input parameter: VirtualMachineSize missing."}
    if ([string]::IsNullOrEmpty($LocalAdministratorUserAccount)) {throw "Input parameter: LocalAdministratorUserAccount missing."}
    if ([string]::IsNullOrEmpty($LocalAdministratorPassword)) {throw "Input parameter: LocalAdministratorPassword missing."}
    if ([string]::IsNullOrEmpty($VirtualNetworkSubnetName)) {throw "Input parameter: VirtualNetworkSubnetName missing."}
    if ([string]::IsNullOrEmpty($HybridUseBenefit)) {throw "Input parameter: HybridUseBenefit missing."}
    if ([string]::IsNullOrEmpty($PublicIpType)) {throw "Input parameter: PublicIpType missing."}
    if ($EnableBootDiagnostics -eq $null) {throw "Input parameter: EnableBootDiagnostics missing."}
    if ($StartVmAfterProvisioning -eq $null) {throw "Input parameter: StartVmAfterProvisioning missing."}
    if ($UsePremiumStorage -eq $null) {throw "Input parameter: UsePremiumStorage missing."}
    if ([string]::IsNullOrEmpty($DomainName)) {throw "Input parameter: DomainName missing."}
    if ($ManagedOS -eq $true) {
        if([string]::IsNullOrEmpty($CustomScript)) {throw "Input parameter: CustomString is missing. "}
    }
    if (($CustomScript.Trim() -or $CustomScriptArguments.Trim()) -and $ManagedOS -eq $false) {
        throw "Input Parameter: CustomScript/CustomScriptArgument is set but ManagedOS was set to False."
    }

    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    [boolean]$JoinDomain = $false
    if($DomainName -ilike "none")
    {
        $JoinDomain = $false
    }
    else
    {
        $JoinDomain = $true
    }

    # Fetch Domain Name and password if the domainjoin parameter is set.
    if ($JoinDomain) {

        $DomainsList = $Runbook.Configuration.VirtualMachine.ActiveDirectory.Domains
        $RequiredDomainInfo = $DomainsList | Where-Object -FilterScript {$_.Name -like $DomainName}

        if($null -eq $RequiredDomainInfo)
        {
            throw "Domain Details not found in configuration : $DomainName"
        }
        if($RequiredDomainInfo.Name.Count -gt 1)
        {
            throw "More than one matching domain information found in configuration: $DomainName"
        }

        $DomainUser = "$($RequiredDomainInfo.AccountName)@$DomainName"
        $VaultName = $Runbook.Configuration.Vaults.KeyVault.Name
        $domainAdminPassKey = $RequiredDomainInfo.AccountName
        $VaultInfo = Get-AzureKeyVaultSecret -VaultName "$VaultName"  -Name $domainAdminPassKey
        $DomainPwd = $VaultInfo.SecretValueText

        $String1 = @"
{
    "Name" : "$DomainName",
    "User" : "$DomainUser",
    "Restart" : "true",
    "Options" : "3"
}
"@
       
        $String2 = @"
{
    "Password" : "$DomainPwd"
}
"@
        Write-Verbose "Retrieved values from configuration: ${DomainName}, ${DomainUser}, ${VaultName} "
    }

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    Write-Verbose "Received Input:"
    Write-Verbose "  VirtualMachineTemplateName : ${VirtualMachineTemplateName}"
    Write-Verbose "  VirtualMachineResourceGroupName : $VirtualMachineResourceGroupName"
    Write-Verbose "  PrefixVmName : $PrefixVmName"
    Write-Verbose "  VirtualMachineOSVersion : $VirtualMachineOSVersion"
    Write-Verbose "  VirtualMachineSize: $VirtualMachineSize"
    Write-Verbose "  VirtualNetworkResourceGroupName : $VirtualNetworkResourceGroupName"
    Write-Verbose "  VirtualNetworkName : $VirtualNetworkName"
    Write-Verbose "  LocalAdministratorUserAccount : $LocalAdministratorUserAccount"
    Write-Verbose "  LocalAdministratorPassword : $LocalAdministratorPassword"
    Write-Verbose "  UsePremiumStorage : $UsePremiumStorage"
    Write-Verbose "  VirtualNetworkSubnetName : $VirtualNetworkSubnetName"
    Write-Verbose "  HybridUseBenefit : $HybridUseBenefit"
    Write-Verbose "  PublicIpType : $PublicIpType"
    Write-Verbose "  EnableBootDiagnostics : $EnableBootDiagnostics"
    Write-Verbose "  StartVmAfterProvisioning : $StartVmAfterProvisioning"
    Write-Verbose "  RequestorUserAccount : $RequestorUserAccount"
    Write-Verbose "  ConfigurationItemId : $ConfigurationItemId"
    Write-Verbose "  JoinDomain : $JoinDomain"
    Write-Verbose "  AvailabilitySetName : $AvailabilitySetName"
    Write-Verbose "  ManagedOS : $ManagedOS"
    Write-Verbose "  CustomScript : $CustomScript"
    Write-Verbose "  CustomScriptArguments : $CustomScriptArguments"

    #region Input checks

    # Performing Resource Group Check
    Write-Verbose "Performing Resource Group Check for resource group ${VirtualMachineResourceGroupName}"
    $ResourceGroupInfo = Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName
    if ($null -eq $ResourceGroupInfo) {
        throw "Resource Group Name ${VirtualMachineResourceGroupName} not found"
    }
    $ResourceGroupLocation = $ResourceGroupInfo.location

    # Performing VmName Check
    $VmNameCode = $Runbook.Configuration.VirtualMachine.Names | Where-Object {$_.Code -eq $VirtualMachineNameCode}
    if (!$VmNameCode) {
        throw "VirtualMachineNameCode: ${VirtualMachineNameCode} not valid!"
    }
	
	#Performing check for Hybrid Use Benifit
	#Set input to lowercase
	if($HybridUseBenefit -ne "yes" -or $HybridUseBenefit -ne "no") {
	    $HybridUseBenefit = $HybridUseBenefit.ToLower()
	}
	#Fixed condition: If a Virtual Machine is not a Windows Machine, we set HybridUseBenefit to no, regardless of the input
	$AllowedHubOperatingSystems = @("Windows 2008-R2-SP1","Windows 2012-Datacenter","Windows 2012-R2-Datacenter","Windows 2016-Datacenter")
	If($HybridUseBenefit -eq "yes") {
	    If(!($VirtualMachineOSVersion.StartsWith("Windows"))) {
		    $HybridUseBenefit = "no"
		}
		ElseIf($AllowedHubOperatingSystems -notcontains $VirtualMachineOSVersion) {
			throw "The HUB feature does not allows Windows 2016-Nano-Server and Windows 2016-Datacenter-with-Containers as Operating System."
		}
	}
	
    # Performing check for Standard Storage Account to store diagnostic logs
    Write-Verbose "Performing check for Standard Storage Account"
    $StorageAccountName = ""
    $DiagnosticStorageAccount = ""
    
    $DiagnosticStorageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.ResourceGroupName -like $VirtualMachineResourceGroupName -and $_.Sku.Tier -like "Standard"} | Select-Object -Unique).StorageAccountName
    if($DiagnosticStorageAccount -eq $null -or $DiagnosticStorageAccount -eq "")
    {
        throw "Standard Storage Account is not present in resource group ${VirtualMachineResourceGroupName} . Required to store diagnostic storage logs like boot diagnostic"
    }

    # Retrieving storage account type
    $StorageAccountType = ""
    if ($UsePremiumStorage -like $True) 
    {
        $StorageAccountType = "Premium_LRS"
    }
    else
    {
        $StorageAccountType = "Standard_LRS"
    }
       
    # Performing VM Size check
    Write-Verbose "Performing VM Size check for size ${VirtualMachineSize}"
    $VirtualMachineSize = $VirtualMachineSize.Replace(" ","_")
    $SizeListAll = Get-AzureRmVMSize -Location $ResourceGroupLocation
    $SizeListStandard = @()
    $SizeListPremium = @()
    forEach ($Size in $SizeListAll) {
        if ($Size.Name.Split("_")[1] -match "S") {   
            # Premium Profile List   
            $SizeListPremium += $Size.Name
        } else {
            # Standard Profile List
            $SizeListStandard+= $Size.Name
        }
    }
    if ($UsePremiumStorage -like $True) {
        $Sizecheck = $SizeListPremium | Where-Object -FilterScript  {$_ -like $VirtualMachineSize}
        if ($null -eq $Sizecheck) {
            throw "Incorrect storage profile ${VirtualMachineSize}. Supported storage profile for premium accounts are : ${SizeListPremium}"
        }
    } else {
        $Sizecheck = $SizeListStandard | Where-Object -FilterScript  {$_ -like $VirtualMachineSize}
        if ($null -eq $Sizecheck) {
            throw "Incorrect storage profile ${VirtualMachineSize}. Supported storage profile for standard accounts are : ${SizeListStandard}"
        }
    }

    # Performing Network Check
    $NetworkCheck = Get-AzureRmVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $VirtualNetworkResourceGroupName | Select-Object -ExpandProperty subnets | Where-Object {$_.Name -like $VirtualNetworkSubnetName}
    if ($NetworkCheck -eq $null) {
        throw "Provide correct values for  VirtualNetworkResourceGroupName : ${VirtualNetworkResourceGroupName} VirtualNetworkName: ${VirtualNetworkName} VirtualNetworkSubnetName: ${VirtualNetworkSubnetName} "
    }

    # OS Version check      
    if ($VirtualMachineOSVersion -match "Windows") {
        $OperatingSystem = $VirtualMachineOSVersion.Split(" ")[1]
        Write-Verbose "Retrieved Windows OS Version : ${OperatingSystem}"
    } else {
        $OperatingSystem = $VirtualMachineOSVersion
        Write-Verbose "Retrieved Linux OS Version : ${OperatingSystem}"
    }

    # Performing Template check
    $template = $Runbook.Configuration.VirtualMachine.Templates | Where-Object {$_.Name -eq $VirtualMachineTemplateName}
    if ($null -eq $template) {
        throw "VirtualMachineTemplateName: ${VirtualMachineTemplateName} does not exist."
    }
    #endregion       

    #Performing Availability Set Check
    if ($AvailabilitySetName -ne "")
    {
        #Check whether the availability set name is exists
        Write-Verbose "Check whether the availability set name is exists"
        $AvailabilitySetCheck = Get-AzureRmAvailabilitySet -ResourceGroupName $VirtualMachineResourceGroupName | where-object { $_.Name -like "$AvailabilitySetName"}#$AvailabilitySetName
        if($AvailabilitySetCheck -eq "" -or $AvailabilitySetCheck -eq $null)
        {
            throw "Availability Set : $AvailabilitySetName does not exists in Resource Group : $VirtualMachineResourceGroupName"
        }
        
        # Check if the Machine count in current Availability Set is already at the maximum
        Write-Verbose "Check Machine count in Availability Set"
        if ( $AvailabilitySetCheck.VirtualMachinesReferences.id.count -eq 200)
        {
            throw "Maximum vm count 200 is reach in an Availability Set : $AvailabilitySetName . Kindly remove a machine from availability set to perform this operation"
        }
        
        # Check if New Vms Virtual Network is same as network in Availability Set if Availability Set contains machines.
        Write-Verbose "Check if New Vms Virtual Network is same as network in Availability Set if Availability Set contains machines"
        if($AvailabilitySetCheck.VirtualMachinesReferences.id.count -gt 0)
        {
            $ExistingVmName = ($AvailabilitySetCheck.VirtualMachinesReferences.id | select -First 1).split("/")[-1]
            $ExistingVmInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $ExistingVmName
            $ExistingNic = ($ExistingVmInfo.NetworkProfile.NetworkInterfaces.id).split("/")[-1]
            $SubetId = (Get-AzureRmNetworkInterface -ResourceGroupName $VirtualMachineResourceGroupName -Name $ExistingNic).IpConfigurations.subnet.id
            $AvailabilitySetVnet = $SubetId.Split("/")[-3]
            if($VirtualNetworkName -ne $AvailabilitySetVnet)
            {
                throw "Availability Set : $AvailabilitySetName supports network : $AvailabilitySetVnet of Resource Group $($SubetId.Split("/")[4])"
            }
        }

        if ($HybridUseBenefit -eq "yes")
        {
            $DeploymentType = "AvailabilityYesLicenseYes"
        }
        elseif ($HybridUseBenefit -eq "no")
        {
            $DeploymentType = "AvailabilityYesLicenseNo"
        }
    }
    else
    {
        if ($HybridUseBenefit -eq "yes")
        {
            $DeploymentType = "AvailabilityNoLicenseYes"
        }
        elseif ($HybridUseBenefit -eq "no")
        {
            $DeploymentType = "AvailabilityNoLicenseNo"
        }
    }
    
    #LocalAdministrtorUserAccount Check
    if (!($LocalAdministratorUserAccount -cmatch "^([a-zA-Z0-9\-_$&.]){0,14}[a-zA-Z0-9\-_$&]{1}$" -and $LocalAdministratorUserAccount -notlike "Administrator"))
    {
        throw "Please enter a valid User Name. Windows admin user name cannot be more than 14 characters long, contains 'Administrator' as an username, end with a period(.), or contain the following characters: \ / `" [ ] : | < > + = ; , ? * @."
    }
   
    #LocalAdministratorPassword Check
    if (!($LocalAdministratorPassword -cmatch '^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*(_|[^\w])).{8,123}$'))
    {
        throw "Please enter a valid Password. The supplied password must be between 8-123 characters long and must satisfy at least 3 of password complexity requirements from the following: 1) Contains an uppercase character 2) Contains a lowercase character 3) Contains a numeric digit 4) Contains a special character 5) Control characters are not allowed."
    }
    

    Write-Verbose "Reconnecting to management subscription to call Get-VMName runbook"
    # Connect to the management subscription
    $ManagementContext = Connect-AtosManagementSubscription

    # Retrieve the prefix for New Vm Name after all input checks were succesfull
    $Params = @{
        "SubscriptionId" = $SubscriptionId
        "VirtualMachineResourceGroupName" = $VirtualMachineResourceGroupName
        "VirtualMachineNameCode" = $VirtualMachineNameCode
        "RequestorUserAccount" = $RequestorUserAccount
        "ConfigurationItemId" = $ConfigurationItemId
    }

    $GetVMOutput = Start-AzureRmAutomationRunbook -AutomationAccountName $Runbook.AutomationAccount  -Name "Get-VmName" -ResourceGroupName $Runbook.ResourceGroup -Parameters $Params -Wait

     $GetVMOutput1 = $GetVMOutput.Split(":").Trim(" ")[0]
     $GetVMOutput2 = $GetVMOutput.Split(":").Trim(" ")[1]

    if ($GetVMOutput1 -like "VM*") {
        Write-Verbose "VM name generated"
    }
    elseif($GetVMOutput1 -like "FAILURE*")
    {
        throw  "Error : Failed to get output from Get-VmName, Get-VMName Runbook Output is - $GetVMOutput2"
    }
   else{
        throw  "Error : Failed to get output from Get-VmName, Get-VMName Runbook Output is - $GetVMOutput2"
    }
    
    $PrefixVmName = $GetVMOutput.Split(":").Trim(" ")[1]
    if ($GetVMOutput -like "VM: *") {
        $PrefixVmName = $GetVMOutput.Split(":").Trim(" ")[1]
        if ($PrefixVmName.Length -ne 15) {
            throw "Error : Retrieved Vm Name: ${PrefixVmName} does not follow the Vm naming guideline"
        } else {
            Write-Verbose "Retrieved PrefixVMName as ${PrefixVmName}"
        }
    } else {
        throw "Error : Failure in retrieving VM Name from Get-VMName"
    }
    $VmNameCheck = $true

    # Connecting again to the Customer Subscription (now to create the VM)
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    if ($VirtualMachineTemplateName -like "Windows-VM-Deployment-Template") {
        $templateparameters = @{
            "vNetResourceGroup" = "$VirtualNetworkResourceGroupName"
            "VMResourceGroup" = "$VirtualMachineResourceGroupName"
            "virtualMachineName" = "$PrefixVmName"
            "virtualMachineSize" = "$VirtualMachineSize"
            "adminUsername" = "$LocalAdministratorUserAccount"
            "storageAccountType" = "$StorageAccountType"
            "virtualNetworkName" = "$VirtualNetworkName"
            "adminPassword" = "$LocalAdministratorPassword"
            "subnetName" = "$VirtualNetworkSubnetName"
            "HybridUseBenefit" = "$HybridUseBenefit"
            "publicIpAddressType" = "$PublicIpType"
            "bootDiagnostics" = $EnableBootDiagnostics
            "WindowsOSVersion" = $OperatingSystem
            "diagnosticsStorageAccountName" = "$DiagnosticStorageAccount"
            "DeploymentType" = $DeploymentType
            "AvailabilitySetName" = $AvailabilitySetName
        }

        # ARM Template Check
        Write-Verbose "Performing ARM template check with supplied parameters"
        $TemplateCheckOp = Test-AzureRmResourceGroupDeployment -ResourceGroupName $VirtualMachineResourceGroupName -TemplateUri "https://$($Runbook.StorageAccount).blob.core.windows.net/$($template.Filename)" -TemplateParameterObject $templateparameters
        if ($TemplateCheckOp -ne $null) {
           throw "$($TemplateCheckOp.Message)"
        }
       
        # Deployment of ARM Template
        Write-Verbose "Deploying VMs using ARM template ..."
        Write-Verbose "Deployment name = DeployWindowsVM-${PrefixVmName}-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))"
        $Operation = New-AzureRmResourceGroupDeployment `
            -Name "DeployWindowsVM-${PrefixVmName}-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))" `
            -ResourceGroupName $VirtualMachineResourceGroupName `
            -TemplateUri "https://$($Runbook.StorageAccount).blob.core.windows.net/$($template.Filename)" `
            -TemplateParameterObject $templateparameters `
            -ErrorAction SilentlyContinue
        if ($Operation.ProvisioningState -eq "Failed") {
            $ARMError = (((Get-AzureRmResourceGroupDeploymentOperation -DeploymentName "$($Operation.DeploymentName)" -ResourceGroupName $($Operation.ResourceGroupName)).Properties)).StatusMessage.error | Format-List | Out-String
            $ARMError = $ARMError.Trim()
            throw "Error: ARM deployment failed `n${ARMError}"
        }
    } elseif ($VirtualMachineTemplateName -like "Linux-VM-Deployment-Template") {
        $templateparameters = @{ 
            "vNetResourceGroup" = "$VirtualNetworkResourceGroupName" 
            "VMResourceGroup" = "$VirtualMachineResourceGroupName" 
            "virtualMachineName" = "$PrefixVmName" 
            "virtualMachineSize" = "$VirtualMachineSize" 
            "adminUsername" = "$LocalAdministratorUserAccount" 
            "storageAccountType" = "$StorageAccountType" 
            "virtualNetworkName" = "$VirtualNetworkName" 
            "adminPassword" = "$LocalAdministratorPassword" 
            "subnetName" = "$VirtualNetworkSubnetName" 
            "publicIpAddressType" = "$PublicIpType" 
            "bootDiagnostics" = $EnableBootDiagnostics 
            "LinuxOSVersion" = $OperatingSystem 
            "diagnosticsStorageAccountName" = "$DiagnosticStorageAccount" 
            "AvailabilitySetName" = "$Availabilitysetname" 
        }  
        
        # ARM Template Check
        Write-Verbose "Performing ARM template check with supplied parameters"
        $TemplateCheckOp = Test-AzureRmResourceGroupDeployment -ResourceGroupName $VirtualMachineResourceGroupName -TemplateUri "https://$($Runbook.StorageAccount).blob.core.windows.net/$($template.Filename)" -TemplateParameterObject $templateparameters
        if ($TemplateCheckOp -ne $null) {
            throw "$($TemplateCheckOp.Message)"
        }
   
        # Deployment of ARM Template
        Write-Verbose "Deploying VMs using ARM template ..."
        Write-Verbose "Deployment name = DeployLinuxVM-${PrefixVmName}-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))"
        $Operation = New-AzureRmResourceGroupDeployment `
            -Name "DeployLinuxVM-${PrefixVmName}-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))" `
            -ResourceGroupName $VirtualMachineResourceGroupName `
            -TemplateUri "https://$($Runbook.StorageAccount).blob.core.windows.net/$($template.Filename)" `
            -TemplateParameterObject $templateparameters `
            -ErrorAction SilentlyContinue
        if ($Operation.ProvisioningState -eq "Failed") {
            $ARMError = (((Get-AzureRmResourceGroupDeploymentOperation -DeploymentName "$($Operation.DeploymentName)" -ResourceGroupName $($Operation.ResourceGroupName)).Properties)).StatusMessage.error|Format-List | Out-String
            $ARMError = $ARMError.Trim()
            throw "Error: ARM deployment failed `n$ARMError"
        }
        # Write-Output $Operation
    }

    #Vm has been created we are not going to revert the counter number any more after this point.
    $VmNameCheck = $false
    $DomainJoinFail = $False

    
    if ($JoinDomain -eq $true -and $VirtualMachineOSVersion -like "*Windows*") {
    # Adding VmExtension on Windows Machine
        Write-Verbose "Setting AzureRmVMExtension on Windows Machine"
           
        $Location = (Get-AzureRmResourceGroup -Name "$VirtualMachineResourceGroupName" ).location
        $SetExtension = Set-AzureRmVMExtension -ResourceGroupName "$VirtualMachineResourceGroupName" -ExtensionType "JsonADDomainExtension" `
                -Name "joinDomain-$DomainName" -Publisher "Microsoft.Compute" -TypeHandlerVersion "1.0" -Location $Location `
                -VMName "$PrefixVmName" -SettingString $string1 `
                -ProtectedSettingString $string2
        $GetExtension = (Get-AzureRmVMExtension -ResourceGroupName "$VirtualMachineResourceGroupName" -VMName "$PrefixVmName" -Name "joinDomain-${DomainName}")
        Write-Verbose "The status of extension is $($GetExtension.ProvisioningState)"
        
        $vm = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $PrefixVmName
        if($GetExtension.ProvisioningState -eq "Succeeded")
        {
            Write-Verbose "VM is successfully added to domain $DomainName"
            
            # Update tag Value
            $tags = $vm.Tags
            if ($tags.atosMaintenanceString2 -eq $null) {
                Write-Verbose "No atosMaintenanceString2 tag.  Adding tag and key/value pair."
                $tags += @{"atosMaintenanceString2"="{`"Domain`":`"${DomainName}`"}"}
            } 

            ## Update VM with updated tag set
            $result = Set-AzureRmResource -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force
            $returnMessage += "`nUpdated tags on VM to include domain"

        }
        else
        {
            Write-Verbose "Failed to add VM to domain $DomainName"
            
            # Update tag Value
            $tags = $vm.Tags
            if ($tags.atosMaintenanceString2 -eq $null) {
                Write-Verbose "No atosMaintenanceString2 tag.  Adding tag and key/value pair."
                $tags += @{"atosMaintenanceString2"="{`"Domain`":`"NotJoined`"}"}
            } 

            ## Update VM with updated tag set
            $result = Set-AzureRmResource -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force
            $returnMessage += "`nUpdated tags on VM to include domain"
            $DomainJoinFail = $true
        }
        $RemoveExtension = $GetExtension| Remove-AzureRmVMExtension -Force
        Write-Verbose "The status of remove extension $($RemoveExtension.IsSuccessStatusCode)"
    }
    else{

        if ($JoinDomain -eq $true -and $VirtualMachineOSVersion -notlike "*Windows*") 
        {
            # Raise warning if operating system is not like Windows
            $DomainJoinFail = $true
            Write-Verbose "Set DomainJoinFail to true since operating system is not Windows"
        }
        # Updating Tag for workgroup machine
        $vm = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $PrefixVmName
        # Update tag Value
        $tags = $vm.Tags
        if ($tags.atosMaintenanceString2 -eq $null) {
            Write-Verbose "No atosMaintenanceString2 tag.  Adding tag and key/value pair."
            $tags += @{"atosMaintenanceString2"="{`"Domain`":`"NotJoined`"}"}
        } 

        ## Update VM with updated tag set
        $result = Set-AzureRmResource -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tags -Force
        $returnMessage += "`nUpdated tags on VM to include domain"
    }

    # Get Public IP Address of the VM
    Write-Verbose "Getting IP details"
    $vm = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $PrefixVmName
    try {
        # Get NIC0 name using old method
        $nicResourceName = (Get-AzureRmResource -ResourceId $vm.NetworkInterfaceIDs[0]).ResourceName
    } catch {
        Write-Verbose "Failed to get NIC name using original method.  Trying updated method"
        try {
            # Get NIC0 name using new method
            $nicResourceName = $vm.NetworkProfile.NetworkInterfaces[0].id.Split('/')[-1]
        } catch {
            throw "Failed to retrieve NIC0 name"
        }
    }
    $nic = Get-AzureRmNetworkInterface -ResourceGroupName $VirtualMachineResourceGroupName -Name $nicResourceName
    $privateip = $nic.IpConfigurations.PrivateIpAddress

    # ==================
    # Managed OS Section
    # ==================

    # Post Deployment Custom Script Extension
    if ($ManagedOS -eq $true) {
        Write-Verbose "Starting Managed OS tasks. "

        # Connect to the management subscription
        Write-Verbose "Connect to default subscription"
        $ManagementContext = Connect-AtosManagementSubscription

        # Custom Script Extension Variables
        $CustomScriptName = "PostDeploymentScript"
        $CustomScriptStorageContainer = "postdeployment"
        $CustomScriptRun = $CustomScript + " " + $CustomScriptArguments

        # Get Azure Storage Key
        $mgmtStorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount

        # Connecting again to the Customer Subscription (now to execute post deployment script)
        Write-Verbose "Connect to customer subscription"
        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections
        
        # Attempt to apply a Custom Script Extension to the VM.    
        Write-Verbose "Attempting to apply Custom Script Extension to VM. "
        try {
            # Set all parameters for Set-AzureRMVMCustomScriptExtension cmdlet. 
            $HashArguments = @{
                Name                = $CustomScriptName;
                Run                 = $CustomScriptRun;
                ResourceGroupName   = $VirtualMachineResourceGroupName;
                VmName              = $vm.Name; 
                Location            = $vm.Location;
                StorageAccountName  = $Runbook.StorageAccount;
                StorageAccountKey   = $mgmtStorageAccountKey[0].Value;
                ContainerName       = $CustomScriptStorageContainer;
                FileName            = $CustomScript
            }
            
            $CustomScriptStatus = Set-AzureRMVMCustomscriptExtension @HashArguments -SecureExecution
            Write-Verbose "Custom Script Extension Success Code: $($CustomScriptStatus.IsSuccessStatusCode) "
            $postDeploymentMessage = "`nThe Post Deployment Script $($CustomScript) was also successfully run. "
        }
        catch {
            Write-Verbose "Custom Script Extension Failure. "
            Write-Verbose "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]" 
            $postDeploymentMessage = "`nThe Post Deployment Script $($CustomScript) did not complete successfully. Please check the VM. "
            $ManagedOSFail = "Failed"
        }

        # If the Post Deployment Script Successfully executed, then remove the Custom Script Extension from the VM. 
        Write-Verbose "Attempting to remove Custom Script Extension from VM. "
        if ($CustomScriptStatus.IsSuccessStatusCode -eq $true) {
            try {
                $RemoveCustomScriptExtension = Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $VirtualMachineResourceGroupName -VMName $vm.Name -Name $CustomScriptName -Force
                Write-Verbose "Removal of Custom Script Extension Success Status Code: $($RemoveCustomScriptExtension.IsSuccessStatusCode)"
                if ($($RemoveCustomScriptExtension.IsSuccessStatusCode) -eq $true) {
                }
                
            }
            catch {
                Write-Verbose "Removal of Custom Script Extension Success Status Code: $($RemoveCustomScriptExtension.IsSuccessStatusCode)"
                Write-Verbose "Failed to remove Custom Script Extension post script execution. "
                Write-Verbose "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]" 
                if ($($RemoveCustomScriptExtension.IsSuccessStatusCode) -eq $false) {
                    $ManagedOSFail = "Unremoved"
                }
            }
        }
    }
    else {
        $postDeploymentMessage = ""
    }

    # =========================
    # End of Managed OS Section
    # =========================

    # Stopping VM after provisioning
    if ($StartVmAfterProvisioning -like $false) {
        Write-Verbose "Deallocating Vm : ${PrefixVmName}"
        $StopVM = Stop-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $PrefixVmName -Force
        Write-Verbose "Successfully deallocated VM: ${PrefixVmName}"
    }

    $resultMessage = "Successfully created VM: ${PrefixVmName}"
	if ($JoinDomain)
    {
        if($VirtualMachineOSVersion -notlike  "*Windows*")
        {
            $domainJoinResultMessage = ", The VM was created successfully but not joined to a domain as domain join is not supported for this Operating System template."
            Write-Verbose "The VM was created successfully but not joined to a domain as domain join is not supported for this Operating System template."
        }
		elseif ($DomainJoinFail)
		{
			$domainJoinResultMessage = ", but it failed to join the domain: $DomainName"
		}
		else
		{
			$domainJoinResultMessage = " and it has been successfully joined to domain: $DomainName"    
		}
	}

    # Prepare notification text with results from VM Creation
    Write-Verbose "Sending email to customer"
    $From = $Runbook.Configuration.EmailNotifications.FromEmailAddress
    $Subject = $resultMessage
    if ($StartVmAfterProvisioning) {
        $notificationMessage = "Virtual Machine: ${PrefixVmName} with private IP address: ${privateip} has been created${domainJoinResultMessage}. ${postDeploymentMessage}. The local admin User account name is $($templateparameters.adminUsername). `n`nKind regards,`nAtos MPC Azure team"
        $Body = "Dear requestor,`n`n${notificationMessage}"
    } else {
        $notificationMessage = "Virtual Machine: ${PrefixVmName} has been created${domainJoinResultMessage}. The local admin User account name is $($templateparameters.adminUsername). A private IP address will be allocated when the VM is first started. `n`nKind regards,`nAtos MPC Azure team"
        $Body = "Dear requestor,`n`n${notificationMessage}"
    }
	
    # When enabled send the e-mail notification from Azure runbook
    if (![string]::IsNullOrEmpty($Runbook.Configuration.EmailNotifications.Enabled)) {
		if ($Runbook.Configuration.EmailNotifications.Enabled -eq "true") {
	
		$SMTPServer = $Runbook.Configuration.EmailNotifications.SMTPServer
		$SMTPPort = $Runbook.Configuration.EmailNotifications.SMTPport
		$credential = new-object Management.Automation.PSCredential $Runbook.Configuration.EmailNotifications.FromEmailAddress, ($Runbook.Configuration.EmailNotifications.Password | ConvertTo-SecureString -AsPlainText -Force)
		$To = $Runbook.Configuration.EmailNotifications.DestinationEmailAddresses

		Send-MailMessage -From $From -to $To -Subject $Subject `
			-Body $Body -SmtpServer $SMTPServer -port $SMTPPort -UseSsl `
			-Credential $credential
		}
	}
    # Throw Error (WARNING) if machine domain join operation fails
    if ($DomainJoinFail)
    {
        throw "VM: ${PrefixVmName} is created but failed to join domain: $DomainName"
    }
    
    #
    switch ($ManagedOSFail) {
        "Failed" {throw "VM: ${PrefixVmName} is created but Custom Script ${CustomScript} failed to execute. "; break}
        "Unremoved" {throw "VM: ${PrefixVmName} is created and Custom Script ${CustomScript} executed successfully, but failed to remove from the VM post execution. "; break}
    }

    $resultcode = "SUCCESS"
} 


catch {
    
    if ($VmNameCheck) {
        # Connect to the management subscription
        Write-Verbose "Reconnecting with admin subscription to revert the Counter table value due to failure in VM creation"
        $ManagementContext = Connect-AtosManagementSubscription

        $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
        $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
        $VmNamePrefix = $PrefixVmName.SubString(0, 11)

        $Value = $PrefixVmName.Substring($PrefixVmName.Length-4, 4)
        if ($Value -match "^[\d\.]+$") { #if numeric
            [int]$num = $PrefixVmName.SubString($PrefixVmName.Length-4, 4)
            $newcount = $num-1
            [String]$NewValue = "{0:D4}" -f $newcount

            $UpdateCounter = 0
	        $UpdateSuccess = $False
            do {
		        $UpdateCounter++
                $TableName = $Runbook.Configuration.Customer.NamingConventionSectionA + "vmcountertable"
		        $CounterTable = Get-AzureStorageTable -Context $StorageContext | Where-Object {$_.CloudTable.Name -eq $TableName}
		        if (!($CounterTable)) {
			        $CounterTable = New-AzureStorageTable -Name $TableName -Context $StorageContext
		        }
		
		        #Updating CounterTable
		        $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
                $query.FilterString = "PartitionKey eq 'VmName' and RowKey eq '${VmNamePrefix}'"
		
		        $CounterInfo = $CounterTable.CloudTable.ExecuteQuery($query)
		        $Etag = $CounterInfo.etag
		        if ($CounterInfo -ne $null) { 
			        $entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity 'VmName', $VmNamePrefix
			        $entity2.Properties.Add("NewValue", $NewValue)
			        $entity2.ETag = $Etag
			        try {
				        $result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Replace($entity2))	
				        if ($result.HttpStatusCode -eq "204") {
					        $UpdateSuccess = $true
					        $VmName = $PartitionKey + $NewValue
					        $CounterBasedVmName = $VmName
				        }
			        } catch {
                        Write-Verbose "ERROR updating table"
				        # Conflict Error expected
			        }
		        }
	        } until (($UpdateSuccess -eq $true) -or ($UpdateCounter -gt 100))
        } else {
            throw "Something is not correct: ${PrefixVmName}"
        }
    }

	if ($DomainJoinFail -or $ManagedOSFail) {
	    $resultcode = "WARNING"
	}
	else {
	    $resultcode = "FAILURE"
	}

    $resultMessage = $_.ToString()

    if ($resultMessage.Contains('Resource Microsoft.Compute/virtualMachines')) {
        $beginJson = $resultMessage.IndexOfAny("{")
        $endJson = $resultMessage.LastIndexOf("}")
        $jsonError = $resultMessage.Substring($beginJson, ($endJson - $beginJson) + 1) | ConvertFrom-JSON
        $resultMessage = $jsonError.Error.code + ": " + $jsonError.Error.target + ". " + $jsonError.Error.message
    }

}

Write-Output $resultcode
Write-Output $resultMessage
Write-Output $notificationMessage