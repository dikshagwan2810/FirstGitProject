
function Connect-AtosManagementSubscription {
    Write-Verbose "Connecting to default management subscription"
    $Connection = Get-AutomationConnection -Name DefaultRunAsConnection
    $AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Connection.TenantID -ApplicationId $Connection.ApplicationID -CertificateThumbprint $Connection.CertificateThumbprint

    $SubscriptionName = $Context.Subscription.SubscriptionName
    if ([string]::IsNullOrEmpty($SubscriptionName)) {$SubscriptionName = $Context.Subscription.Name}
    Write-Verbose "Connected to subscription '${SubscriptionName}' [${SubscriptionId}]"

    return $AddAccount.Context

    <#
    .SYNOPSIS
    Connects to the DefaultRunAs connection

    .DESCRIPTION
    Connects to the DefaultRunAs connection and returns the context

    .EXAMPLE
    $mgmtContext = Connect-AzureRmDefaultSubscription
    #>
}

function Connect-AtosCustomerSubscription {
    Param (
        # The ID of the Azure subscription to connect to
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $SubscriptionID,

        # A hashtable of subscription IDs to subscription names
        [Parameter(Mandatory = $true)]
        [Object] [ValidateNotNullOrEmpty()]
        $Connections
    )

    Write-Verbose "Connecting to subscription '${SubscriptionId}'"
    $ConnectionName = $Connections.Item($SubscriptionId)
    if (([string]::IsNullOrEmpty($ConnectionName))) {
        throw "Subscription '${SubscriptionId}' not found in RunAsConnectionRepository."
    }

    $Connection = Get-AutomationConnection -Name $ConnectionName
    if ($Connection -eq $null) {
        throw "Automation connection '${ConnectionName}' not found."
    }

    $Counter = 0
    $SubscriptionConnect = $false
    do {
        $Counter++
        try {
            $AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Connection.TenantID -ApplicationId $Connection.ApplicationID -CertificateThumbprint $Connection.CertificateThumbprint -SubscriptionId $SubscriptionId
            # Wait for subscriptions to become available
            Start-Sleep -Seconds 3
            $Context = Select-AzureRmSubscription -SubscriptionId $SubscriptionId
            # Wait for subscription to become active
            Start-Sleep -Seconds 3

            # Check that the current context is using required subscription
            [string]$ActiveSubscriptionId = (Get-AzureRmContext).Subscription.Id
            if ([string]::IsNullOrEmpty($ActiveSubscriptionId)) {
                # Check again with the old style object, just in case
                [string]$ActiveSubscriptionId = (Get-AzureRmContext).Subscription.SubscriptionId
            }
            if ($ActiveSubscriptionId -ne $SubscriptionId) {
                Write-Verbose "Connection attempt ${Counter}: Selected subscription not active."
            } else {
                $SubscriptionConnect = $true
            }
        } catch {
            Write-Verbose "Error connecting to subscription on attempt ${Counter}."
            Write-Verbose $_.ToString()
        }
    } until (($SubscriptionConnect -eq $true) -or ($Counter -ge 5))

    if ($ActiveSubscriptionId -ne $SubscriptionId) {
        throw "Failed to activate subscription ${SubscriptionId} after ${Counter} attempts"
    }

    $SubscriptionName = $Context.Subscription.SubscriptionName
    if ([string]::IsNullOrEmpty($SubscriptionName)) {$SubscriptionName = $Context.Subscription.Name}
    Write-Verbose "Connected to subscription '${SubscriptionName}' [${SubscriptionId}]"

    return $Context

    <#
    .SYNOPSIS
    Connects to a specified subscription by ID

    .DESCRIPTION
    Connects to a specified subscription by ID

    .EXAMPLE
    $CustomerContext = Connect-AzureRmSubscription -SubscriptionID aa21151e-22b9-411b-b83c-6f22fc37e71f -Connections $Runbook.Connections
    #>
}

function Get-AtosRunbookObjects {
    Param (
        # The ID of the runbook
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $RunbookJobId
    )

    # Find the automation account or resource group of this Job
    Write-Verbose "Get Runbook objects from job ${RunbookJobId}"
    $AutomationResource = Find-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts
    foreach ($AutomationAccount in $AutomationResource) {
        $Job = Get-AzureRmAutomationJob -ResourceGroupName $AutomationAccount.ResourceGroupName -AutomationAccountName $AutomationAccount.Name -Id $RunbookJobId -ErrorAction SilentlyContinue
        if (!([string]::IsNullOrEmpty($Job))) {
            $RunbookResourceGroupName = $Job.ResourceGroupName
            $AutomationAccountName = $Job.AutomationAccountName
            break;
        }
    }

    if ($RunbookResourceGroupName -eq $null) {
        throw "Failed to retrieve job details"
    }

    Write-Verbose "Get StorageAccount"
    $RunbookStorageAccount = Get-AzureRmStorageAccount | Where-Object {$_.ResourceGroupName -eq $RunbookResourceGroupName}
    $RunbookStorageAccountName = $RunbookStorageAccount.StorageAccountName
    if ($RunbookStorageAccount -eq $null -or $RunbookStorageAccount -eq "") {
        throw "No Storage Account found in Resource Group '${RunbookResourceGroupName}'"
    } elseif ($RunbookStorageAccount.count -gt 1) {
        throw "Resource Group '${RunbookResourceGroupName}'' contains $($RunbookStorageAccount.count) storage accounts where 1 was expected"
    }

    Write-Verbose "Retrieve configuration data"
    $Configuration = (Get-AzureRmAutomationVariable -ResourceGroupName $RunbookResourceGroupName -AutomationAccountName $AutomationAccountName -Name "MPCAConfiguration").Value | ConvertFrom-JSON
    if ($Configuration -eq $null) {
        throw "Failed to retrieve MPCAConfiguration JSON"
    }

    Write-Verbose "Get allowed Connections"
    $Connections = @{}
    $Configuration.MPCAConfiguration.Subscriptions | ForEach-Object {$Connections += @{$_.id = $_.ConnectionAssetName}}

    $RunbookObjects = New-Object PSObject -Property @{
        ResourceGroup     = $RunbookResourceGroupName
        AutomationAccount = $AutomationAccountName
        StorageAccount    = $RunbookStorageAccountName
        Configuration     = $Configuration.MPCAConfiguration
        Connections       = $Connections
        JobId             = $RunbookJobId
    }

    return $RunbookObjects

    <#
    .SYNOPSIS
    Gets useful information about the runbook objects

    .DESCRIPTION
    Collects details about various aspects of the current job and returns them in a PSObject.  Details returned are:
     - [string] ResourceGroup     = Runbook Resource Group Name
     - [string] AutomationAccount = Runbook Automation Account Name
     - [string] StorageAccount    = Runbook Storage Account Name
     - [string] JobId             = Job ID of the current runbook run
     - [object] Configuration     = The MPCA configuration object for this environment
     - [hashtable] Connections    = Allowed subscription IDs <-> subscription names

    .EXAMPLE
    $mgmtContext = Connect-AzureRmDefaultSubscription
    #>
}

function Get-AtosLocationCode {
    Param (
        [Parameter(Mandatory = $true)]
        [object]
        $MPCAConfiguration,

        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionID,

        [Parameter(Mandatory = $true)]
        [String]
        $Location
    )

    $AzureLocation = Get-AzureRmLocation |
        Where-Object {
        ($_.Location -Match $Location) -or
        ($_.DisplayName -match $Location)
    }
    if ($AzureLocation -eq $null) {
        throw "Cannot find an Azure location for ${Location}"
    }

    # Get our subscription
    $SubscriptionConfig = $MPCAConfiguration.Subscriptions | Where-Object {$_.ID -match $SubscriptionID}
    if ($SubscriptionConfig -eq $null) {
        throw "Cannot find subscription '${SubscriptionID}' in the MPCA configuration object"
    }

    # Attempt to get the location code from the Azure Location property
    $LocationCode = ($SubscriptionConfig.AllowedRegions | Where-Object {$_.Name -match $AzureLocation.Location}).NamingStandardCode
    if ($LocationCode -eq $null) {
        # Attempt to get the location code from the Azure DisplayName property
        $LocationCode = ($SubscriptionConfig.AllowedRegions | Where-Object {$_.Name -match $AzureLocation.DisplayName}).NamingStandardCode
    }

    if ($LocationCode -ne $null) {
        return $LocationCode
    } else {
        throw "Cannot find location code in allowed regions for location ${Location}"
    }
}

function Set-AtosResourceTags {
    Param (
        # The name of the resource.  If not supplied then the tags will be applied to the resource group
        [Parameter(Mandatory = $false)]
        [string]$ResourceName,

        # The name of the resource group
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        # The tags to be applied to this object
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$NewTags,

        # Replace all existing tags with the new set
        [switch]$RemoveExisting
    )

    if ([string]::IsNullOrEmpty($ResourceName)) {
        $IsResourceGroup = $true
        $Resource = Get-AzureRmResourceGroup -Name $ResourceGroupName
        if ($Resource -eq $null) {
            throw "Failed to retrieve resource group '${ResourceGroupName}'"
        }
    } else {
        $Resource = Get-AzureRmResource -Name $ResourceName -ResourceGroupName $ResourceGroupName
        if ($Resource -eq $null) {
            throw "Failed to retrieve resource '${ResourceName}' from resource group '${ResourceGroupName}'"
        }
    }

    if ($RemoveExisting -eq $true) {
        # Ignore the existing tags and start from scratch
        $ResourceTags = $NewTags
    } else {
        $ResourceTags = $Resource.Tags
        if ($ResourceTags -eq $null) {
            # No tags retrieved, so set variable to an empty hashtable
            $ResourceTags = @{}
        }

        # Add or update the tags for this Resource
        forEach ($key in $NewTags.Keys) {
            if ($ResourceTags.ContainsKey($key)) {
                $ResourceTags.$key = $NewTags.$key
            } else {
                try {
                    $ResourceTags.Add($key, $NewTags.$key)
                } catch [System.Management.Automation.MethodInvocationException] {
                    if ($Error[0].Exception.InnerException -match "Item has already been added") {
                        # Apparently the key is there even though we couldn't see it, so just update it.
                        $ResourceTags.$key = $NewTags.$key
                    }
                }
            }
        }
    }

    if ($IsResourceGroup -eq $true) {
        $result = Set-AzureRmResourceGroup -Tag $ResourceTags -Id $Resource.ResourceId
    } else {
        $result = Set-AzureRmResource -Tag $ResourceTags -ResourceId $Resource.ResourceId -Confirm:$false -Force
    }

    return $result

    <#
    .SYNOPSIS
    Updates the tags on a named resource or resource group

    .DESCRIPTION
    Updates the tags on a named resource or resource group.  You have the option to update and/or add all tags specified leaving any other tags in place or, using the -RemoveExisting switch, remove all existing tags and replace them with only the ones specified.

    .EXAMPLE
    $result = Set-AzureRmResourceTags -ResourceGroupName $ResourceGroupName -NewTags $Tags -RemoveExisting
    This will remove any existing tags and replace them with the new ones.  This will apply to the resource group itself as a resource name was not specified

    .EXAMPLE
    $result = Set-AzureRmResourceTags -ResourceGroupName $ResourceGroupName -ResourceName $VmName -NewTags $Tags
    This update any existing tags with the new values specified in the $tags variable.  Any tags in $Tags that do not exist will be created.  Any existing tags that are not listed in $Tags will be left in place.  This will apply to the VM $VmName resource group itself as the resource name was specified
    #>
}

function Get-AtosJsonTagValue {
    Param (
        # The Virtual Machine object to read tags from
        [Parameter(Mandatory = $true)]
        $VirtualMachine,

        # The name of the tag that contains the value you need.  i.e. atosMaintenanceString2
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $TagName,

        # The name of the key that you want to retrieve the value for.  i.e. RSVault
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $KeyName
    )

    $Tags = $VirtualMachine.Tags
    $KeyValue = ""
    Write-Verbose "Checking for ${TagName}\${KeyName} tag"
    if ($Tags.$TagName -ne $null) {
        Write-Verbose "  Found ${TagName} tag"
        $TagObject = $Tags.$TagName | ConvertFrom-JSON
        if ([string]::IsNullOrEmpty($TagObject.$KeyName)) {
            Write-Verbose "Key ${KeyName} not found in ${TagName} tag"
        } else {
            $KeyValue = $TagObject.$KeyName
            Write-Verbose "  Found ${KeyName} with value ${KeyValue}"
        }
    } else {
        Write-Verbose "Cannot find ${TagName} tag"
    }
    return $KeyValue
}

function Set-AtosJsonTagValue {
    Param (
        # The Virtual Machine object to write tags to
        [Parameter(Mandatory = $true)]
        $VirtualMachine,

        # The name of the tag that will contain the value you need.  i.e. atosMaintenanceString2
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $TagName,

        # The name of the key that you want to update the value of.  i.e. RSVault
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $KeyName,

        # The value for the key.  i.e. gla-dev1-p-rsv-euwe-BackupTestGroup
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNull()]
        $KeyValue
    )

    $Tags = $VirtualMachine.Tags
    if ($Tags.$TagName -eq $null) {
        Write-Verbose "No ${TagName} tag - adding tag and key/value pair."
        $Tags += @{"$TagName" = "{`"${KeyName}`":`"${KeyValue}`"}"}
    } else {
        $TagObject = $Tags.$TagName | ConvertFrom-JSON
        if ($TagObject.$KeyName -eq $null) {
            Write-Verbose "$KeyName key doesn't exist in ${TagName} tag - adding key/value pair."
            $TagObject | Add-Member -MemberType NoteProperty -Name $KeyName -Value $KeyValue
        } else {
            Write-Verbose "${KeyName} key found - updating."
            $TagObject.$KeyName = $KeyValue
        }
        $Tags.$TagName = $TagObject | ConvertTo-JSON -Compress
    }

    ## Update VM with updated tag set
    $result = Set-AzureRmResource -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $Tags -Force
    Write-Verbose "Updated ${TagName}\${KeyName} on VM"

    return $result
}

function Remove-AtosJsonTagValue {
    Param (
        # The Virtual Machine object to remove tags from
        [Parameter(Mandatory = $true)]
        $VirtualMachine,

        # The name of the tag that will contain the value you want to remove.  i.e. atosMaintenanceString2
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $TagName,

        # The name of the key that you want to remove from $TagName.  i.e. RSVault
        [Parameter(Mandatory = $true)]
        [string] [ValidateNotNullOrEmpty()]
        $KeyName
    )
    $Tags = $VirtualMachine.Tags

    if ($Tags.$TagName -eq $null) {
        Write-Verbose "No ${TagName} tag.  Nothing to remove."
        $SetTagResult = $VirtualMachine
    } else {
        Write-Verbose "Found ${TagName} tag."
        $TagObject = $Tags.$TagName | ConvertFrom-JSON
        $TagObject.PSObject.Properties.Remove($KeyName)
        $Tags.$TagName = $TagObject | ConvertTo-JSON -Compress
        Write-Verbose "Setting ${TagName} to $($TagObject | ConvertTo-JSON -Compress)"
        $SetTagResult = Set-AzureRmResource -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $Tags -Force
    }
    return $SetTagResult
}

function Disable-OMSAgent {
    param(
        # The name of the Resource Group for the VM
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineResourceGroupName,

        # The name of the VM to enable for IaaSVM backup
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineName,

        # The name of the VM to enable for IaaSVM backup
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The Runbook object to get details of subscription
        [Parameter(Mandatory = $true)]
        $Runbook,

        # Flag to enable maintenance mode
        [Parameter(Mandatory = $true)]
        [boolean]
        $EnableMaintenanceMode
    )

    try {
        $VM = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        if ($VM -eq $null) {
            Write-Verbose "Unable to find VM"
            throw "Unable to find VM"
        }

        $VmStatus = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status
        $VmPowerStatus = $VmStatus.Statuses | Where-Object {$_.code -like "PowerState*"}
        if ($VmPowerStatus.code -ne "PowerState/running") {
            Write-Verbose "VM is not in running state"
            throw "VM is not in running state"
        }
        $VmLocation = $VM.Location
        $OSType = $($VM.StorageProfile.OsDisk.OsType).ToString().ToLower()
        Write-Verbose "OS type is '${OSType}'"
        Switch ($OSType) {
            $null {
                Write-Verbose "OS Type is NULL"
                throw "OS type is NULL"
            }
            "windows" {
                $ExtensionName = 'MicrosoftMonitoringAgent'
                $ExtensionType = 'MicrosoftMonitoringAgent'
            }
            "linux" {
                $ExtensionName = 'OmsAgentForLinux'
                $ExtensionType = 'OmsAgentForLinux'
            }
            default {
                Write-Verbose "OSType '${OSType}' is not recognised"
                throw "OSType '${OSType}' is not recognised"
            }
        }

        Write-Verbose "Checking OMS workspace"
        $SubscriptionConfig = $Runbook.Configuration.Subscriptions | Where-Object {$_.Id -eq $SubscriptionId}
        $WorkspaceName = $SubscriptionConfig.OMSWorkspaceName
        $Workspace = Get-AzureRmOperationalInsightsWorkspace | Where-Object {$_.name -eq $WorkspaceName}

        if ($Workspace -eq $null) {
            Write-Verbose "Unable to find OMS Workspace '${WorkspaceName}'"
            throw "Unable to find OMS Workspace '${WorkspaceName}'"
        }

        if ($Workspace.Count -ne 1) {
            Write-Verbose "There are more than 1 workspaces named '${WorkspaceName}'"
            throw "There are more than 1 workspaces named '${WorkspaceName}'"
        }

        $WorkspaceId = $Workspace.CustomerId
        $WorkspaceKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $Workspace.ResourceGroupName -Name $Workspace.Name).PrimarySharedKey

        $OmsExtension = Get-AzureRmVMExtension -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName -name $ExtensionName -ErrorAction SilentlyContinue
        if ($OmsExtension) {
            Write-Verbose "Removing Montioring Agent"
            $jobstatus = Remove-AzureRmVMExtension -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName -Name $ExtensionName -Force
            Write-Verbose "Job status is $($jobstatus.IsSuccessStatusCode)"

            #Validation
            $VirtualMachine = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
            $VmExtensions = $VirtualMachine.Extensions.VirtualMachineExtensionType
            Write-Verbose "VMExtensions found = '$($VmExtensions -join ' | ')'"

            if ($VmExtensions -contains $ExtensionType) {
                throw "VirtualMachineExtensionType: ${ExtensionType} was not removed from VM ${VirtualMachineName}"
            }
        } else {
            Write-Verbose "Agent ${ExtensionType} is not installed - Nothing to do"
        }

        #Setting Monitoring tag value on VM
        $VM = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        if ($EnableMaintenanceMode -eq $true) {
            $SetTagValue = Set-AtosJsonTagValue -TagName atosMaintenanceString2 -KeyName MonStatus -KeyValue MaintenanceMode -VirtualMachine $VM
            $status = "SUCCESS"
            $resultMessage = "VM : ${VirtualMachineName} is under maintenance mode"
        } else {
            $SetTagValue = Set-AtosJsonTagValue -TagName atosMaintenanceString2 -KeyName MonStatus -KeyValue NotMonitored -VirtualMachine $VM
            $status = "SUCCESS"
            $resultMessage = "VM : ${VirtualMachineName} removed from monitoring"
        }
    } catch {
        $status = "FAILURE"
        $resultMessage = "Disable monitoring failed on Virtual Machine : $VirtualMachineName `nError : $($_.ToString())"
    }

    $result = $status, $resultMessage

    return $result
}

function Enable-OMSAgent {
    Param (
        # The name of the Resource Group for the VM
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineResourceGroupName,

        # The name of the VM to enable for IaaSVM backup
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineName,

        # The name of the VM to enable for IaaSVM backup
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The Runbook object to get details of subscription
        [Parameter(Mandatory = $true)]
        $Runbook
    )
    try {

        $ErrorCode = 0 # ErrorCode = 0 states no Error, ErrorCode = 1 states Error
        $ErrorMessage = ""

        $VM = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        if ($VM -eq $null) {
            Write-Verbose "Unable to find VM"
            throw "Unable to find VM"
        }

        $VmStatus = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName -Status
        $VmPowerStatus = $VmStatus.Statuses | Where-Object {$_.code -like "PowerState*"}
        if ($VmPowerStatus.code -ne "PowerState/running") {
            Write-Verbose "VM is not in running state"
            throw "VM is not in running state"
        }


        $VmLocation = $VM.Location
        $OSType = $($VM.StorageProfile.OsDisk.OsType)
        Write-Verbose "OS type is '${OSType}'"
        Switch ($OSType) {
            $null {
                Write-Verbose "OS Type is NULL"
                throw "OS type is NULL"
            }
            "windows" {
                $ExtensionName = 'MicrosoftMonitoringAgent'
                $ExtensionType = 'MicrosoftMonitoringAgent'
            }
            "linux" {
                $ExtensionName = 'OmsAgentForLinux'
                $ExtensionType = 'OmsAgentForLinux'
            }
            default {
                Write-Verbose "OSType '${OSType}' is not recognised"
                throw "OSType '${OSType}' is not recognised"
            }
        }

        Write-Verbose "Checking OMS workspace"
        $SubscriptionConfig = $Runbook.Configuration.Subscriptions | Where-Object {$_.Id -eq $SubscriptionId}
        $WorkspaceName = $SubscriptionConfig.OMSWorkspaceName
        $Workspace = Get-AzureRmOperationalInsightsWorkspace | Where-Object {$_.name -eq $WorkspaceName}

        if ($Workspace -eq $null) {
            Write-Verbose "Unable to find OMS Workspace '${WorkspaceName}'"
            throw "Unable to find OMS Workspace '${WorkspaceName}'"
        }

        if ($Workspace.Count -ne 1) {
            Write-Verbose "There are more than 1 workspaces named '${WorkspaceName}'"
            throw "There are more than 1 workspaces named '${WorkspaceName}'"
        }

        $WorkspaceId = $Workspace.CustomerId
        $WorkspaceKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $Workspace.ResourceGroupName -Name $Workspace.Name).PrimarySharedKey

        $OmsExtension = (Get-AzureRmVMExtension -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName -name $ExtensionName -ErrorAction SilentlyContinue).ProvisioningState
        if ($OmsExtension -eq $null) {
            $jobstatus = Set-AzureRmVMExtension -ResourceGroupName $VirtualMachineResourceGroupName `
                -VMName $VirtualMachineName `
                -Name $ExtensionName `
                -Publisher 'Microsoft.EnterpriseCloud.Monitoring' `
                -ExtensionType $ExtensionType `
                -TypeHandlerVersion '1.0' `
                -Location $VmLocation `
                -SettingString "{'workspaceId': '${WorkspaceId}'}" `
                -ProtectedSettingString "{'workspaceKey': '${WorkspaceKey}'}"
            Write-Verbose "Job status is $($jobstatus.IsSuccessStatusCode)"
            if ($jobstatus.IsSuccessStatusCode -eq $true) {
                Write-Verbose "Installed OMS agent successfully"
            } else {
                Write-Verbose "Unable to install agent."
                throw "Unable to install OMS agent"
            }
        } else {
            Write-Verbose "Agent is already installed"
        }

        #Validation
        $VM = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        $VmExtensions = $VM.Extensions.VirtualMachineExtensionType
        Write-Verbose "VMExtensions found = '$($VmExtensions -join ' | ')'"

        $SetTagValue = Set-AtosJsonTagValue -TagName 'atosMaintenanceString2' -KeyName 'MonStatus' -KeyValue 'Monitored' -VirtualMachine $VM

        if ($VmExtensions -contains $ExtensionType) {
            $status = "SUCCESS"
            $resultMessage = "VM : ${VirtualMachineName} added in monitoring"
        } else {
            throw "VirtualMachineExtensionType: ${ExtensionType} not found"
        }

    } catch {
        $status = "FAILURE"
        $resultMessage = "Enable monitoring failed on Virtual Machine : $VirtualMachineName `nError : $($_.ToString())"
    }
    $Result = $status, $resultMessage
    return $Result
}

function Set-SnowVmPowerStatus {
    Param (
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The name of the Resource Group that the VM is in
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineResourceGroupName,

        # The name of the VM to act upon
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineName,

        # Set true for a runnning VM, false for a stopped VM
        [Parameter(Mandatory = $true)]
        [bool]
        $Running
    )

    # Generate required URI
    $BaseURI = $Runbook.Configuration.Endpoints.ServiceNow.BaseURI
    if ($Running -eq $true) {
        $URI = "${BaseURI}/startVM/${SubscriptionId}/${VirtualMachineResourceGroupName}/${VirtualMachineName}"
    } else {
        $URI = "${BaseURI}/stopVM/${SubscriptionId}/${VirtualMachineResourceGroupName}/${VirtualMachineName}"
    }
    Write-Verbose "SNow URI: ${URI}"

    # Generate Credentials
    [string]$SnowUserName = $Runbook.Configuration.Endpoints.ServiceNow.UserName
    Write-Verbose "SNow User: ${SnowUserName}"

    $VaultName = $Runbook.Configuration.Vaults.KeyVault.Name
    # Replace . for - as the keyvault can't handle dots in the name
    $VaultInfo = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SnowUserName.Replace('.', '-')
    [string]$SnowPassword = $VaultInfo.SecretValueText

    Write-Verbose "Generate Credentials"
    $UserPass = "${SnowUserName}:${SnowPassword}"
    $EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserPass))
    $AuthHeaderValue = "Basic ${EncodedCreds}"

    # Generate Headers
    $Headers = @{
        "Accept"        = "application/json";
        "Content-Type"  = "application/json";
        "Authorization" = $AuthHeaderValue
    }
    $body = ""

    # Request update from SNow
    $RequestResult = Invoke-RestMethod -Uri $URI -Method Post -body $body -Headers $Headers

    # Parse results
    try {
        $SNowResult = $RequestResult.result | ConvertFrom-Json
    } catch {
        Write-Verbose "SNOW result = ${RequestResult}"
        throw "Failed to convert SNOW output from JSON"
    }

    switch ($SNowResult.status) {
        "Success" {
            if ($SNowResult.request -ne '') {
                return "SUCCESS - $($SNowResult.message) [SNow requestID $($SNowResult.request)]"
            } else {
                return "SUCCESS - $($SNowResult.message)"
            }
        }
        "Failure" {
            return "FAILURE - $($SNowResult.message)"
        }
        default {
            return "FAILURE - Unknown response from SNow: '${RequestResult}'"
        }
    }
}

function Set-SnowVmMonitoringStatus {
    Param (
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The name of the Resource Group that the VM is in
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineResourceGroupName,

        # The name of the VM to act upon
        [Parameter(Mandatory = $true)]
        [String]
        $VirtualMachineName,

        # The monitoring state to set
        [Parameter(Mandatory = $true)]
        [string] [ValidateSet('Monitored', 'NotMonitored', 'MaintenanceMode')]
        $MonitoringStatus
    )

    # Generate required URI
    $BaseURI = $Runbook.Configuration.Endpoints.ServiceNow.BaseURI
    $URI = "${BaseURI}/${MonitoringStatus}/${SubscriptionId}/${VirtualMachineResourceGroupName}/${VirtualMachineName}"
    Write-Verbose "SNow URI: ${URI}"

    # Generate Credentials
    [string]$SnowUserName = $Runbook.Configuration.Endpoints.ServiceNow.UserName
    Write-Verbose "SNow User: ${SnowUserName}"

    $VaultName = $Runbook.Configuration.Vaults.KeyVault.Name
    # Replace . for - as the keyvault can't handle dots in the name
    $VaultInfo = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SnowUserName.Replace('.', '-')
    [string]$SnowPassword = $VaultInfo.SecretValueText

    Write-Verbose "Generate Credentials"
    $UserPass = "${SnowUserName}:${SnowPassword}"
    $EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserPass))
    $AuthHeaderValue = "Basic ${EncodedCreds}"

    # Generate Headers
    $Headers = @{
        "Accept"        = "application/json";
        "Content-Type"  = "application/json";
        "Authorization" = $AuthHeaderValue
    }
    $body = ""

    # Request update from SNow
    $RequestResult = Invoke-RestMethod -Uri $URI -Method Post -body $body -Headers $Headers

    # Parse results
    try {
        $SNowResult = $RequestResult.result | ConvertFrom-Json
    } catch {
        Write-Verbose "SNOW result = ${RequestResult}"
        throw "Failed to convert SNOW output from JSON"
    }

    switch ($SNowResult.status) {
        "Success" {
            if ($SNowResult.request -ne '') {
                return "SUCCESS - $($SNowResult.message) [SNow requestID $($SNowResult.request)]"
            } else {
                return "SUCCESS - $($SNowResult.message)"
            }
        }
        "Failure" {
            return "FAILURE - $($SNowResult.message)"
        }
        default {
            return "FAILURE - Unknown response from SNow: '${RequestResult}'"
        }
    }
}

function Send-RecoveryPointToSnow {
    [CmdletBinding()]
    Param (
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The Virtual Machine object
        [Parameter(Mandatory = $true)]
        [Object]
        $VirtualMachine,

        # The Recovery Vault object
        [Parameter(Mandatory = $true)]
        [Object]
        $RecoveryVault,

        # The Recovery Point object
        [Parameter(Mandatory = $true)]
        [Object]
        $RecoveryPoint
    )

    # Get display name for actual vault location - required by SNow
    $VaultLocation = (Get-AzureRmLocation | Where-Object {$_.location -eq $RecoveryVault.location}).DisplayName

    # Generate required URI
    $URI = ($Runbook.Configuration.Endpoints.ServiceNowBackupTable.BaseURI).Trim()
    Write-Verbose "SNow URI: ${URI}"

    # Generate Credentials
    [string]$SnowUserName = $($Runbook.Configuration.Endpoints.ServiceNowBackupTable.UserId).Trim()
    Write-Verbose "SNow User: ${SnowUserName}"

    $KeyVaultName = $Runbook.Configuration.Vaults.KeyVault.Name
    # Replace . for - as the keyvault can't handle dots in the name
    try {
        $KeyVaultInfo = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SnowUserName.Replace('.', '-').Replace('@', '-') -ErrorAction Stop
        [string]$SnowPassword = $KeyVaultInfo.SecretValueText
    } catch {
        throw "Failed to retrieve password from keyvault: $($_.ToString())"
    }

    Write-Verbose "Generate Credentials"
    $UserPass = "${SnowUserName}:${SnowPassword}"
    $EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserPass))
    $AuthHeaderValue = "Basic ${EncodedCreds}"

    # Generate Headers
    $Headers = @{
        "Accept"        = "application/json";
        "Content-Type"  = "application/json";
        "Authorization" = $AuthHeaderValue
    }
    $global:body = @"
{
  "u_vm_name": "$($VirtualMachine.Name)",
  "u_vault_name": "$($RecoveryVault.Name)",
  "u_vault_location": "${VaultLocation}",
  "u_vault_resource_group": "$($RecoveryVault.ResourceGroupName)",
  "u_restore_id": "$($RecoveryPoint.RecoveryPointId)",
  "u_recovery_point_time": "$($RecoveryPoint.RecoveryPointTime.ToString('yyyy-MM-dd HH:mm:ss'))",
  "u_recovery_point_type": "adhoc"
}
"@

    Write-Verbose "Body = ${body}"
    # Request update from SNow
    $global:SnowResult = Invoke-RestMethod -Uri $URI -Method POST -body $body -Headers $Headers

    # Parse results
    Write-Verbose "SNOW result = $($SnowResult | ConvertTo-JSON -depth 99 -Compress)"
    switch -regex ($SNowResult.result.sys_id) {
        "[a-fA-F0-9]{32}" {
            "SUCCESS"
            "sys_id: $($SNowResult.result.sys_id)"
        }
        default {
            "FAILURE"
            "Unknown response from SNow: $($SnowResult | ConvertTo-JSON -depth 99 -Compress)"
        }
    }
}

function Set-AtosVmTags {
    param(
        # The name of the Resource Group that the VM is in
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineResourceGroupName,

        # The name of the VM to act upon
        [Parameter(Mandatory = $false)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineName,

        # The value for the costCenter tag.  Leave blank to leave unchanged.
        [Parameter(Mandatory = $false)]
        [String]
        $costCenter,

        # The value for the projectName tag.  Leave blank to leave unchanged.
        [Parameter(Mandatory = $false)]
        [String]
        $projectName,

        # The value for the appName tag.  Leave blank to leave unchanged.
        [Parameter(Mandatory = $false)]
        [String]
        $appName,

        # The value for the supportGroup tag.  Leave blank to leave unchanged.
        [Parameter(Mandatory = $false)]
        [String]
        $supportGroup,

        # The value for the environment tag.  Leave blank to leave unchanged.
        [Parameter(Mandatory = $false)]
        [String]
        $environment,

        # The configuration item ID for this job
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $ConfigurationItem
    )

    # Everything wrapped in a try/catch to ensure SNOW-compatible output
    try {
        [string] $returnMessage = ""

        # Retrieving VM information
        $VirtualMachine = Get-AzureRmVm -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
        if ($VirtualMachine -eq $null) {
            throw "Cannot find VM '${VirtualMachineName}' in resource group '${VirtualMachineResourceGroupName}'"
        }

        $ResourceIdList = @()
        $ResourceIdList += $VirtualMachine.Id
        Write-Verbose "Virtual Machine ResourceId is: $($ResourceIdList[0])"

        # Add any NIC objects to the list of resources to update
        try {
            if ($VirtualMachine.NetworkInterfaceIDs -eq $null) {
                $VirtualMachine.NetworkProfile.NetworkInterfaces | ForEach-Object {
                    Write-Verbose "Adding NIC ResourceId: $($_.id)"
                    $ResourceIdList += $_.id
                }
            } else {
                $ResourceIdList += $VirtualMachine.NetworkInterfaceIDs
            }
        } catch {
            $VirtualMachine.NetworkProfile.NetworkInterfaces | ForEach-Object {
                Write-Verbose "Adding NIC ResourceId: $($_.id)"
                $ResourceIdList += $_.id
            }
        }

        $ResourceGroupTags = Get-AzureRmResourceGroup -Name $VirtualMachineResourceGroupName | Select-Object -ExpandProperty Tags
        if ($ResourceGroupTags) {
            # Override specified tags with values from the resource group
            $environment = $ResourceGroupTags.Environment
            $costcenter = $ResourceGroupTags.Costcenter
        }

        # Update exiting tags with new values
        $ResourceTags = $VirtualMachine.Tags
        $newTags = @{}
        $newTags += @{ControlledByAtos = "True"} # This is always added
        $newTags += @{ManagedOS = "Unprotected"} # This should always be Unprotected for VM's created from Runbooks

        # Update tag values if they are not blank
        if (-not [string]::IsNullOrEmpty($appName)) {$newTags += @{appName = "$appName"}
        }
        if (-not [string]::IsNullOrEmpty($costCenter)) {$newTags += @{costCenter = "$costCenter"}
        }
        if (-not [string]::IsNullOrEmpty($environment)) {$newTags += @{environment = "$environment"}
        }
        if (-not [string]::IsNullOrEmpty($projectName)) {$newTags += @{projectName = "$projectName"}
        }
        if (-not [string]::IsNullOrEmpty($supportGroup)) {$newTags += @{supportGroup = "$supportGroup"}
        }
        if (-not [string]::IsNullOrEmpty($ConfigurationItemId)) {$newTags += @{CI = "$ConfigurationItemId"}
        }

        if ($ResourceTags -eq $null) {
            # No VM tags retrieved, so initialise the variable as a hashtable
            $ResourceTags = @{}
        }

        # Add or update the tags for this Resource
        forEach ($key in $newTags.Keys) {
            Write-Verbose "Checking key ${key}"
            if ($ResourceTags.ContainsKey($key)) {
                Write-Verbose "  Setting ${key} to $($newTags.$key)"
                $ResourceTags.$key = $newTags.$key
            } else {
                Write-Verbose "  Adding ${key} with value $($newTags.$key)"
                try {
                    $ResourceTags.Add($key, $newTags.$key)
                } catch [System.Management.Automation.MethodInvocationException] {
                    if ($Error[0].Exception.InnerException -match "Item has already been added") {
                        # Apparently the key is there even though we couldn't see it, so just update it.
                        Write-Verbose "  !! Item has been added error. Updating instead."
                        $ResourceTags.$key = $newTags.$key
                    } else {
                        Write-Verbose "  !! Unknown error: $($Error[0].Exception.InnerException)"
                    }
                }
            }
        }

        if ($ResourceIdList) {
            foreach ($ResourceId in $ResourceIDList) {
                Write-Verbose "Updating tags for resource: ${ResourceId}"
                # updating tags to new resource
                $result = Set-AzureRmResource -Tag $ResourceTags -ResourceId $ResourceId -Confirm:$false -Force
                if (!$?) {
                    Write-Verbose "Error updating resource: '${ResourceId}'"
                }
            }

            $status = "SUCCESS"
            $returnMessage = "Tags updated"
        } else {
            throw "No ResourceIds to update"
        }
    } catch {
        $status = "FAILURE"
        $returnMessage = $_.ToString()
    }

    return $status, $returnMessage
}

function Get-AtosRecoveryServicesVaultForClient {
    Param(
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String]
        $SubscriptionId,

        # The Azure location of the client
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupLocation,

        # The type of client that requires a vault
        [Parameter(Mandatory = $true)]
        [string] [ValidateSet('AzureVm', 'Windows', 'AzureSQL')]
        $ClientType,

        # The redundancy level of the vault
        [Parameter(Mandatory = $false)]
        [String] [ValidateSet('LocallyRedundant', 'GeoRedundant')]
        $RecoveryVaultRedundancy = "LocallyRedundant"
    )

    # Getting or creating Recovery Services Vault Resource Group
    $RecoveryVaultConfig = $Runbook.Configuration.Vaults.RecoveryServicesVault
    $PrefixSectionA = $Runbook.Configuration.Customer.NamingConventionSectionA
    $PrefixSectionB = ($Runbook.Configuration.Subscriptions | Where-Object {$_.Id -eq $SubscriptionId}).NamingConventionSectionB
    $ResourceGroupNamePrefix = ("${PrefixSectionA}-${PrefixSectionB}-p-rsg").ToLower()
    $RecoveryVaultResourceGroupName = "${ResourceGroupNamePrefix}-$($RecoveryVaultConfig.ResourceGroupSuffix)"
    Write-Verbose "Recovery Vault resource group name: '${RecoveryVaultResourceGroupName}'"

    $VaultCount = 0
    $LocationCode = $Runbook.Configuration.Locations.$ResourceGroupLocation
    Write-Verbose "Retrieved Atos location code '${LocationCode}' from configuration variable"
    $RecoveryVaultNamePrefix = ("${PrefixSectionA}-${PrefixSectionB}-rsv-${LocationCode}").ToLower()

    Write-Verbose "Checking for Recovery Vaults resource group '${RecoveryVaultResourceGroupName}'"
    $RecoveryVaultResourceGroup = Get-AzureRmResourceGroup $RecoveryVaultResourceGroupName -ErrorAction SilentlyContinue
    if ($RecoveryVaultResourceGroup) {
        Write-Verbose "Found resource group ${RecoveryVaultResourceGroupName}"
    } else {
        Write-Verbose "Resource group ${RecoveryVaultResourceGroupName} does not exist.  Creating..."
        New-AzureRmResourceGroup -Name $RecoveryVaultResourceGroupName -Location $ResourceGroupLocation -Verbose -Force | Out-Null
    }

    Write-Verbose "Checking existing vaults"
    $NewVaultNeeded = $false
    $LocalVaults = Get-AzureRmRecoveryServicesVault | Where-Object {$_.Location -eq $ResourceGroupLocation}
    Write-Verbose "$($LocalVaults.Count) existing vaults found."
    $GoodVaults = $LocalVaults |
        Where-Object {$_.Name -match "^${RecoveryVaultNamePrefix}-\d{2}$"} |
        Sort-Object -Property Name
    Write-Verbose "$($GoodVaults.Count) vaults found with correct naming convention."

    $NewVaultNeeded = $true
    if ($GoodVaults.Count -eq 0) {
        Write-Verbose "No vaults with the standard convention found"
        $VaultCount = 1
    } else {
        Write-Verbose "Checking vault capacity"

        forEach ($Vault in $GoodVaults) {
            Set-AzureRmRecoveryServicesVaultContext -Vault $Vault

            switch ($ClientType) {
                "AzureVM" {
                    $Containers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType $ClientType -Status 'Registered'
                    $FreeClients = $($RecoveryVaultConfig.MaxAzureVmClientsPerVault) - $Containers.Count
                    if ($FreeClients -le 0) {
                        Write-Verbose "Vault $($Vault.Name) is at capacity for AzureVm clients."
                    } else {
                        Write-Verbose "Vault $($Vault.Name) has ${FreeClients} free AzureVm registrations. Using this vault."
                        $NewVaultNeeded = $false
                        $BackupVault = $Vault
                    }
                    break
                }
                "Windows" {
                    $Containers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType $ClientType -Status 'Registered' -BackupManagementType MARS
                    $FreeClients = $($RecoveryVaultConfig.MaxWindowsClientsPerVault) - $Containers.Count
                    if ($FreeClients -le 0) {
                        Write-Verbose "Vault $($Vault.Name) is at capacity for Windows clients."
                    } else {
                        Write-Verbose "Vault $($Vault.Name) has ${FreeClients} free Windows registrations. Using this vault."
                        $NewVaultNeeded = $false
                        $BackupVault = $Vault
                    }
                    break
                }
            }
            if ($NewVaultNeeded -eq $false) {break}
        }
    }

    if ($NewVaultNeeded -eq $true) {
        Write-Verbose "No suitable vaults found - creating a new one."
        if ($LocalVaults.Count -ge $RecoveryVaultConfig.MaxVaultsPerRegion) {
            throw "No more vaults allowed! The configuration limit of $($RecoveryVaultConfig.MaxVaultsPerRegion) has been reached."
        }

        # If there are no suitable vaults this would have been set to 1
        # If it's 0 we can assume that potential candidates where found
        if ($VaultCount -eq 0) {
            $VaultCount = 1 + $GoodVaults[-1].Name.Split('-')[4]
        }
        $RecoveryVaultName = "${RecoveryVaultNamePrefix}-$($VaultCount.ToString('00'))"

        Write-Verbose "Creating Recovery Vault '${RecoveryVaultName}' in group '${RecoveryVaultResourceGroupName}'"
        $BackupVault = New-AzureRmRecoveryServicesVault -Location $ResourceGroupLocation -Name $RecoveryVaultName -ResourceGroupName $RecoveryVaultResourceGroupName

        if ($BackupVault) {
            Write-Verbose "Setting redundancy to ${RecoveryVaultRedundancy}"
            Set-AzureRmRecoveryServicesBackupProperties -Vault $BackupVault -BackupStorageRedundancy $RecoveryVaultRedundancy
        } else {
            throw "Failed to create new Recovery Services Vault '${RecoveryVaultName}' with error: $($error[0].Exception.Message)"
        }
    } else {
        Write-Verbose "Using existing Recovery Vault '$($BackupVault.Name)'"
    }

    return $BackupVault
}

function Enable-AtosIaasVmBackup {
    <#
        .SYNOPSIS
        This script enables Iaas VM backup for selected VM.

        .DESCRIPTION
        This script enables Iaas VM backup for selected VM. Once enabled, the VM will be backed up daily and ad-hoc backups are possible

        .NOTES
        Author:     Russ Pitcher
        Company:    Atos
        Email:      russell.pitcher@atos.net
        Created:    2017-02-17
        Updated:    2017-04-05
        Version:    2.0

        .NOTES
        -
    #>
    Param (
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String] [ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
        $SubscriptionId,

        # The name of the VM to enable for IaaS VM backup
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineName,

        # The name of the Resource Group for the VM
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineResourceGroupName,

        # The name of the backup Protection Policy to use
        [Parameter(Mandatory = $false)]
        [String] [ValidateNotNullOrEmpty()]
        $BackupPolicyName = "DefaultPolicy"
    )

    try {
        # Retrieve backup vault name
        $BackupVaultName = ''
        $VM = Get-AzureRmVm -Name $VirtualMachineName -ResourceGroup $VirtualMachineResourceGroupName
        $BackupVaultName = Get-AtosJsonTagValue -VirtualMachine $VM -TagName 'atosMaintenanceString2' -KeyName 'RSVault'

        if ($BackupVaultName -eq '') {
            Write-Verbose "No backup vault information found in tags"
            Write-Verbose "Getting location details from VM ${VirtualMachineName} in resource group ${ResourceGroupName}"
            $VmLocation = $VM.Location
            Write-Verbose "VM location is '${VmLocation}'"
            $BackupVault = Get-AtosRecoveryServicesVaultForClient -SubscriptionId $SubscriptionId -ResourceGroupLocation $VmLocation -ClientType 'AzureVM'
            $BackupVaultName = $BackupVault.Name
        } else {
            Write-Verbose "Getting existing backup vault '${BackupVaultName}'"
            $BackupVault = Get-AzureRmRecoveryServicesVault -Name $BackupVaultName
        }

        Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault
        Write-Verbose "Retrieving Backup Policy"
        $BackupPolicy = Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name $BackupPolicyName

        Write-Verbose "Checking for pre-existing named container"
        $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType "AzureVM" -Status "Registered" -FriendlyName $VirtualMachineName  -ResourceGroupName $VirtualMachineResourceGroupName
        if ($namedContainer -eq $null) {
            Write-Verbose "No named container found in Recovery Services Vault"
            Write-Verbose "Enabling backup on ${VirtualMachineName} in RG ${ResourceGroupName}"
            $EnableResult = Enable-AzureRmRecoveryServicesBackupProtection -Policy $BackupPolicy -Name $VirtualMachineName -ResourceGroupName $VirtualMachineResourceGroupName
        } else {
            Write-Verbose "Found existing named container in Recovery Services Vault"
            $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer -WorkloadType "AzureVM"
            if ($BackupItem -eq $null) {
                throw "Failed to retrieve backup item for VM ${VirtualMachineName}"
            }
            Write-Verbose "Re-enabling backup on ${VirtualMachineName} in RG ${ResourceGroupName}"
            $EnableResult = Enable-AzureRmRecoveryServicesBackupProtection -Policy $BackupPolicy -Item $BackupItem
        }

        if ($EnableResult.Status -eq "Completed") {
            $returnMessage = "Successfully enabled backup of VM ${VirtualMachineName} to vault ${BackupVaultName}"

            Write-Verbose "Adding/updating tag to VM"
            $VM = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
            $result = Set-AtosJsonTagValue -VirtualMachine $VM -TagName 'atosMaintenanceString2' -KeyName 'RSVault' -KeyValue $BackupVaultName
            $returnMessage += "`nUpdated tags on VM to include backup vault"
        } else {
            $returnMessage = "Failed to enable backup of VM ${VirtualMachineName} to vault ${BackupVaultName}"
        }

        if ($returnMessage -match "^Success") {
            $status = "SUCCESS"
        } else {
            $status = "FAILURE"
        }

    } catch {
        $status = "FAILURE"
        $returnMessage = $_.ToString()
    }

    return $status, $returnMessage
}

function Disable-AtosIaasVmBackup {
    <#
        .SYNOPSIS
        This script disables Iaas VM backup for selected VM.

        .DESCRIPTION
        This script disables Iaas VM backup for selected VM.  Once disabled, daily backups will stop and ad-hoc backups are no longer possible until the backup is re-enabled.

        .NOTES
        Author:     Russ Pitcher
        Company:    Atos
        Email:      russell.pitcher@atos.net
        Created:    2017-02-17
        Updated:    2017-04-05
        Version:    2.0

        .NOTES
        -
    #>

    Param (
        # The ID of the subscription to use
        [Parameter(Mandatory = $true)]
        [String] [ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
        $SubscriptionId,

        # The name of the VM to enable for IaaSVM backup
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineName,

        # The name of the VM's Resource Group
        [Parameter(Mandatory = $true)]
        [String] [ValidateNotNullOrEmpty()]
        $VirtualMachineResourceGroupName,

        # Set to remove existing recovery points
        [Parameter(Mandatory = $true)]
        [Bool]
        $RemoveRecoveryPoints
    )

    try {
        ## Get backup vault from atosMaintenanceString2 tag
        Write-Verbose "Getting Recovery Services vault from VM tags"
        $VirtualMachine = Get-AzureRmVm -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
        $VaultName = Get-AtosJsonTagValue -VirtualMachine $VirtualMachine -TagName 'atosMaintenanceString2' -KeyName 'RSVault'

        if ($VaultName -eq "") {
            $returnMessage = "No vault for VM - nothing to do."
            $status = "SUCCESS"
        } else {
            Write-Verbose "Retrieving Backup vault and setting context"
            $BackupVault = Get-AzureRmRecoveryServicesVault -Name $VaultName
            Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault

            $namedContainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType 'AzureVM' -Status 'Registered' -FriendlyName $VirtualMachineName

            $ProtectedItem = Get-AzureRmRecoveryServicesBackupItem -Container $namedContainer[0] -WorkloadType 'AzureVM'

            if ($RemoveRecoveryPoints) {
                Write-Verbose "Disabling backup on ${VirtualMachineName} in RG ${VirtualMachineResourceGroupName} and removing recovery points"
                $result = Disable-AzureRmRecoveryServicesBackupProtection -Item $ProtectedItem -Force -RemoveRecoveryPoints

                Write-Verbose "Removing RSVault from atosMaintenanceString2 tag and updating VM"
                $SetTagResult = Remove-AtosJsonTagValue -VirtualMachine $VirtualMachine -TagName 'atosMaintenanceString2' -KeyName 'RSVault'
            } else {
                Write-Verbose "Disabling backup on ${VirtualMachineName} in RG ${VirtualMachineResourceGroupName}"
                $result = Disable-AzureRmRecoveryServicesBackupProtection -Item $ProtectedItem -Force
                Write-Verbose "Leaving RSVault value in tags as recovery points are not being removed"
            }

            if ($result.Status -eq "Completed") {
                $returnMessage = "Successfully disabled backup of VM ${VirtualMachineName} to vault ${VaultName}"
                if ($RemoveRecoveryPoints) {
                    $returnMessage += " and removed recovery points"
                }
            } else {
                $returnMessage = "Failed to disable backup of VM ${VirtualMachineName} to vault ${VaultName}"
                $returnMessage += "`n${result}"
            }

            if ($returnMessage -match "^Success") {
                $status = "SUCCESS"
            } else {
                $status = "FAILURE"
            }
        }
    } catch {
        $status = "FAILURE"
        $returnMessage = $_.ToString()
    }

    Write-Output $status
    Write-Output $returnMessage
}

Export-ModuleMember -function "Connect-AtosManagementSubscription"
Export-ModuleMember -function "Connect-AtosCustomerSubscription"
Export-ModuleMember -function "Get-AtosRunbookObjects"
Export-ModuleMember -function "Get-AtosLocationCode"
Export-ModuleMember -function "Set-AtosResourceTags"
Export-ModuleMember -function "Disable-OMSAgent"
Export-ModuleMember -function "Enable-OMSAgent"
Export-ModuleMember -function "Set-AtosJsonTagValue"
Export-ModuleMember -function "Get-AtosJsonTagValue"
Export-ModuleMember -function "Remove-AtosJsonTagValue"
Export-ModuleMember -function "Set-SnowVmPowerStatus"
Export-ModuleMember -function "Set-SnowVmMonitoringStatus"
Export-ModuleMember -function "Set-AtosVmTags"
Export-ModuleMember -function "Get-AtosRecoveryServicesVaultForClient"
Export-ModuleMember -function "Enable-AtosIaasVmBackup"
Export-ModuleMember -function "Disable-AtosIaasVmBackup"
Export-ModuleMember -function "Send-RecoveryPointToSnow"