#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    This script renames the Virtual Machine.
    
    .DESCRIPTION
    - Performs renaming of Machine.
    - Renaming Operation is carried out only if the machine is powered off. 
    
    .NOTES
    Author:     Rashmi Kanekar
    Company:    Atos
    Email:      rashmi.kanekar@atos.net
    Created:    2017-01-17
    Updated:    2017-04-24
    Version:    1.1
    
    .Note 
    Enable the Log verbose records of runbook
    Updated to use module and harmonise parameters
#>
Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The name of the VM to act upon
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    # The VM name code to be used
    [Parameter(Mandatory=$true)]
    [String] 
    $VirtualMachineNameCode,

    # The user name of the local Administrator account for Workgroup VMs, or a Domain Administrator account for domain-joined machines
    [Parameter(Mandatory=$false)] 
    [String] 
    $LocalAdministratorUserAccount,

    # The password of the local Administrator account for Workgroup VMs, or a Domain Administrator account for domain-joined machines
    [Parameter(Mandatory=$false)] 
    [String] 
    $LocalAdministratorPassword,

    # The account of the user who requested this operation
    [Parameter(Mandatory=$true)]
    [String]
    $RequestorUserAccount,

    # The configuration item ID for this job
    [Parameter(Mandatory=$true)]
    [String]
    $ConfigurationItemId
)

$VirtualMachineNameCheck = $False
try {
    # Input Validation
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter SubscriptionId missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineName)) {throw "Input parameter VmName missing"}
    if ([string]::IsNullOrEmpty($VirtualMachineNameCode)) {throw "Input parameter VirtualMachineNameCode  missing"}
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter RequestorUserAccount missing"}
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter ConfigurationItemId missing"}

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

    # Retrieving VM information
    Write-Verbose "Retrieving VM information for Vm: $VirtualMachineName of VirtualMachineResourceGroupName: $VirtualMachineResourceGroupName"
    $VmInfo = Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName 
    if (!($VMInfo -ne $null -and $VMInfo -ne "")) {
        throw "VM ${VirtualMachineName} in Resource Group ${VirtualMachineResourceGroupName} not found"
    }
                    
    # VM status check
    Write-Verbose "Chechking the status of Vm..."
    $VmStatus = ((Get-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -VMName $VirtualMachineName -Status).Statuses | Where-Object {$_.code -like "PowerState/*"}).code
    if ($VmStatus -like "PowerState/running") {
        throw "VM needs to be stopped before Performing renaming of VM operation"
    }
    Write-Verbose "Retrieved VM status ${VmStatus}"

    Write-Verbose "Reconnecting to management subscription to call Get-VMName runbook"
    # Reconnect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    #Domain Join Check 
    $DomainCheck = $VmInfo.Extensions.id | Where-Object {$_ -like "*joinDomain-*"}
    if ($DomainCheck) {
        # Domain Join VM 
        # Retrieving the Domain UserName and Password
        [string]$DomainName = $Runbook.Configuration.VirtualMachine.ActiveDirectory.Domains[0].Name
        [string]$DomainUser = "$($Runbook.Configuration.VirtualMachine.ActiveDirectory.Domains[0].AccountName)@${DomainName}"
        [string]$VaultName = $Runbook.Configuration.Vaults.KeyVault.Name
        $domainAdminPassKey = $Runbook.Configuration.VirtualMachine.ActiveDirectory.Domains[0].AccountName
        $VaultInfo = Get-AzureKeyVaultSecret -VaultName $VaultName  -Name $domainAdminPassKey
        $DomainPwd = $VaultInfo.SecretValueText
    } else {
        #Workgroup Machine
        if ([string]::IsNullOrEmpty($LocalAdministratorUserAccount)) {throw "Input parameter LocalAdministratorUserAccount missing"}
        if ([string]::IsNullOrEmpty($LocalAdministratorPassword)) {throw "Input parameter LocalAdministratorPassword missing"}
    }

    # Retrieve the prefix for New Vm Name after all input checks were succesfull
    $Params = @{
        "SubscriptionId" = $SubscriptionId
        "VirtualMachineResourceGroupName" = $VirtualMachineResourceGroupName
        "VirtualMachineNameCode" = $VirtualMachineNameCode
        "RequestorUserAccount" = $RequestorUserAccount
        "ConfigurationItemId" = $ConfigurationItemId
    }

    Write-Verbose "Getting the new name for the VM"



Write-Verbose "Using the following parameters:"
$Params.GetEnumerator() | ForEach-Object {
    Write-Verbose " -> $($_.Key.PadLeft(31)) = $($_.Value)"
}
Write-Verbose "AA = $($Runbook.AutomationAccount)"
Write-Verbose "RG = $($Runbook.ResourceGroup)"



    $GetVMOutput = Start-AzureRmAutomationRunbook -AutomationAccountName $Runbook.AutomationAccount -Name "Get-VmName" -ResourceGroupName $Runbook.ResourceGroup -Parameters $Params -Wait

    $PrefixVmName = $GetVMOutput.Split(":").Trim(" ")[1]
    Write-Verbose "Retrieved PrefixVMName as ${PrefixVmName}"
    $VirtualMachineNameCheck = $true

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    #region Renaming VM from OS 
    $DomainCheck = $VmInfo.Extensions.id | Where-Object {$_ -like "*joinDomain-*"}
    if ($DomainCheck) {
        # Domain Machine
        $UserName = $DomainUser
        $UserPassword = $DomainPwd
    } else {
        # Workgroup Machine
        $UserName = $LocalAdministratorUserAccount
        $UserPassword = $LocalAdministratorPassword
    }

    Write-Verbose "Starting machine ${VirtualMachineName}"
    $StartVM = Start-AzureRmVM -ResourceGroupName $VirtualMachineResourceGroupName -Name $VirtualMachineName
    $VmLocation = $VmInfo.Location
    [string]$ContainerExtensionArmTemplatePath = $Runbook.Configuration.VirtualMachine.Templates.ScriptExtensionArmTemplate

    Write-Verbose "ContainerExtensionArmTemplatePath =  ${ContainerExtensionArmTemplatePath}"
    [string]$ContainerScriptPath = $Runbook.Configuration.VirtualMachine.Templates.ScriptExtensionPowerShellScript
    Write-Verbose "ContainerScriptPath =  ${ContainerScriptPath}"

    $BlobContainerName = $($ContainerScriptPath.Split('/'))[0]
    Write-Verbose "BlobContainerName = ${BlobContainerName}"

    $ScriptLocalPath = $ContainerScriptPath.SubString($BlobContainerName.Length + 1)
    Write-Verbose "ScriptLocalPath = ${ScriptLocalPath}"

    $FileUri = "https://$($Runbook.StorageAccount).blob.core.windows.net/${ContainerScriptPath}" 
    $FileUri = $FileUri.trim()
    $TemplateUri = "https://$($Runbook.StorageAccount).blob.core.windows.net/${ContainerExtensionArmTemplatePath}"

    $TemplateParameterObject = @{
        "vmName" = $VirtualMachineName
        "location" = $VmLocation
        "fileUris" = $FileUri
        "scriptLocalPath" = $ScriptLocalPath
        "UserName" = $UserName
        "NewVmName" = $PrefixVmName
        "UserPassword" = $UserPassword
    }

    Write-Verbose "TemplateParameterObject:"
    $TemplateParameterObject.GetEnumerator() | ForEach-Object {
        Write-Verbose "  $($_.Key) = $($_.Value)"
    }

    # ARM Template Check
    Write-Verbose "Performing ARM template check with supplied parameters"
    $TemplateCheckOp = Test-AzureRmResourceGroupDeployment -ResourceGroupName $VirtualMachineResourceGroupName  -TemplateUri $TemplateUri -TemplateParameterObject $TemplateParameterObject
    if ($TemplateCheckOp -ne $null) {
        throw "$($TemplateCheckOp.Message)"
    }
        
    # Deployment of ARM Template
    Write-Verbose "Deploying VM Extension using ARM template"
    $DeploymentName = "RenameVM-${PrefixVmName}-$(((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))"
    $Operation = New-AzureRmResourceGroupDeployment -ResourceGroupName $VirtualMachineResourceGroupName -TemplateUri $TemplateUri -TemplateParameterObject $TemplateParameterObject -Name $DeploymentName -ErrorAction SilentlyContinue
    if ($Operation.ProvisioningState -eq "Failed") {
        $ARMError = (((Get-AzureRmResourceGroupDeploymentOperation -DeploymentName "$($Operation.DeploymentName)" -ResourceGroupName $($Operation.ResourceGroupName)).Properties)).StatusMessage.error | Format-List | Out-String
        $ARMError = $ARMError.Trim()
        throw "Error: ARM deployment ${DeploymentName} failed `n$ARMError"
    }
    #endregion

     #Old VM Information
    $ResourceGroupName = $VmInfo.ResourceGroupName
    $Location = $VmInfo.Location
    $DataDisks  =  $VmInfo.StorageProfile.DataDisks
    $OsType  =  $VmInfo.StorageProfile.OsDisk.OsType
    $OsDiskUri = $VmInfo.StorageProfile.OsDisk.Vhd.Uri
    $DiskName = $VmInfo.StorageProfile.OsDisk.Name
    $OsDiskCaching = $VmInfo.StorageProfile.OsDisk.Caching

    # Removing OLD VM
    Write-Verbose "Removing the old VM ${VirtualMachineName}"
    $VmInfo | Remove-AzureRmVm -Force | Out-Null

    # Renaming VM in the VM object
    $VmInfo.Name = $PrefixVmName
        
    # Setting the OS Disk
    Write-Verbose "Setting the OS disk for VM"
    $VmInfo.StorageProfile.OsDisk.OsType = $null
    $VmInfo.StorageProfile.ImageReference = $Null
    $VmInfo.OSProfile = $null
    if ($OsType -like "Windows") {
        $VmInfo = Set-AzureRmVMOSDisk -VM $VmInfo -VhdUri $OsDiskUri -name $DiskName -CreateOption attach -Caching $OsDiskCaching -Windows 
    } elseif ($OsType -like "Linux") {
        $VmInfo = Set-AzureRmVMOSDisk -VM $VmInfo -VhdUri $OsDiskUri -name $DiskName -CreateOption attach -Caching $OsDiskCaching -Linux 
    }

    # Attaching Data Disk to VM Object
    Write-Verbose "Attaching data disk to VM"
    $VmInfo.StorageProfile.DataDisks = $null
    forEach ($DataDisk in $DataDisks) {
        $VmInfo = Add-AzureRmVMDataDisk -VM $VmInfo -VhdUri $DataDisk.Vhd.Uri `
            -Name $DataDisk.Name -CreateOption "Attach" `
            -Caching $DataDisk.Caching -DiskSizeInGB $DataDisk.DiskSizeGB `
            -Lun $DataDisk.Lun
    }  

    # Recreating VM 
    Write-Verbose "Recreating Vm with name ${PrefixVmName}"
    New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -Vm $VmInfo -WarningAction Ignore | Out-Null

    $RenameVmInfo = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $PrefixVmName
    if (!($RenameVmInfo -eq $null -or $RenameVmInfo -eq "")) {
        $resultMessage = "Successfully renamed VM to : ${PrefixVmName}"
    }

    $resultcode = "SUCCESS"
} catch {
    if ($VirtualMachineNameCheck) {
        Write-Verbose "Reconnecting with admin subscription to revert the Counter table value due to failure in VM creation"
        $ManagementContext = Connect-AtosManagementSubscription

        $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
        $StorageContext = New-AzureStorageContext -StorageAccountName $Runbook.StorageAccount -StorageAccountKey $StorageAccountKey[0].Value
        $VmNamePrefix = $PrefixVmName.SubString(0, 11)

        $Value = $PrefixVmName.Substring($PrefixVmName.Length-4, 4)
        if ($Value -match "^[\d\.]+$") {  #if numeric
            [int]$num = $PrefixVmName.Substring($PrefixVmName.Length-4, 4)
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
    	        $Query.FilterString = "PartitionKey eq 'VmName' and RowKey eq '${VmNamePrefix}'"
    	
    	        $CounterInfo = $CounterTable.CloudTable.ExecuteQuery($query)
    	        $Etag = $CounterInfo.etag
    	        if ($CounterInfo -ne $null) {  
    		        $entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity 'VmName', $VmNamePrefix
    		        $entity2.Properties.Add("NewValue",$NewValue)
    		        $entity2.ETag = $Etag
    		        try {
    			        $result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Replace($entity2))	
    			        if ($result.HttpStatusCode -eq "204") {
    				        $UpdateSuccess = $true
    				        $VmName = $VmNamePrefix + $NewValue
    				        $CounterBasedVmName = $VmName
    			        }
    		        } catch {
                        Write-Verbose "ERROR updating table"
    			        # Conflict Error expected
    		        }
    	        }
            } until (($UpdateSuccess -eq $true) -or ($UpdateCounter -gt 100))
        } else {
            Write-Verbose "Something is not correct: ${PrefixVmName}"
        }
    }

    $resultcode = "FAILURE"
    $resultMessage = $_.ToString()
}

Write-Output $resultcode
Write-Output $resultMessage