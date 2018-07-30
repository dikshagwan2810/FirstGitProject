#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    This script generates the VM Name as per the naming convention.
    
    .INPUTS
    $VmResourceGroup -  The name of azure resource group of VM
    $VmName - The name of virtual machine
    $Key - Specifies the Character code like ivm,sql
    $SnowUserAccount - Account name of snow user
    $SnowCiID - ID of snow user
    
    .OUTPUTS
    Displays processes step by step during execution
    
    .NOTES
    Author:     Rashmi Kanekar
    Company:    Atos
    Email:      rashmi.kanekar@atos.net
    Created:    2017-02-02
    Updated:    2017-04-20
    Version:    1.1
    
    .Note 
    Enable the Log verbose records of runbook
#>

param(
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String]
    $SubscriptionId,

    # The name of the Resource Group that the VM is in
    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineResourceGroupName,

    [Parameter(Mandatory=$true)] 
    [String] 
    $VirtualMachineNameCode,

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
    # Input Validation
    if ([string]::IsNullOrEmpty($SubscriptionId)) {throw "Input parameter SubscriptionId missing"} 
    if ([string]::IsNullOrEmpty($VirtualMachineResourceGroupName)) {throw "Input parameter VirtualMachineResourceGroupName missing"} 
    if ([string]::IsNullOrEmpty($VirtualMachineNameCode)) {throw "Input parameter VirtualMachineNameCode missing"} 
    if ([string]::IsNullOrEmpty($RequestorUserAccount)) {throw "Input parameter RequestorUserAccount missing"} 
    if ([string]::IsNullOrEmpty($ConfigurationItemId)) {throw "Input parameter ConfigurationItemId missing"} 
    
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    Connect-AtosManagementSubscription | Out-Null

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    # FINISH management subscription code
    $Subscription = $Runbook.Configuration.Subscriptions | Where-Object {$_.Id -eq $SubscriptionId}
    $VmNamePrefix = $Runbook.Configuration.Customer.NamingConventionSectionA + $Subscription.NamingConventionSectionB
    Write-Verbose "VmNamePrefix = ${VmNamePrefix}"
    if ($VmNamePrefix.ToLower() -notMatch '^[a-z0-9]{7}$') {throw "VmNamePrefix '${VmNamePrefix}' is incorrect.  Please check NamingConventionSection entries in the MPCA configuration file"}
    $NamingconventionSectionC = ($VirtualMachineResourceGroupName.Substring(9,1)).ToLower()
    Write-Verbose "NamingConventionSectionC = ${NamingconventionSectionC}"
    if ($VirtualMachineNameCode.Length -gt 3) {
        throw "Number of character in VirtualMachineNameCode '${VirtualMachineNameCode}' exceeds the maximum size of 3."
    }

    $VmNameCodeCheck = $Runbook.Configuration.VirtualMachine.Names | Where-Object {$_.Code -eq $VirtualMachineNameCode}
    Write-Verbose "VmNameCodeCheck = ${VmNameCodeCheck}"
    if (!$VmNameCodeCheck) {
        throw "Namecode: ${VirtualMachineNameCode} not valid!"
    }

    $RowKey = $VmNamePrefix + $NamingconventionSectionC + $VirtualMachineNameCode
    Write-Verbose "RowKey = ${RowKey}"

    $TableName = $Runbook.Configuration.Customer.NamingConventionSectionA + "vmcountertable"
    Write-Verbose "TableName = ${TableName}"

    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $Runbook.StorageAccount -StorageAccountKey $StorageAccountKey[0].Value
    $UpdateCounter = 0
    $UpdateSuccess = $False
    do {
        $UpdateCounter++
        Write-Verbose "UpdateCounter = ${UpdateCounter}"
        $CounterTable = Get-AzureStorageTable -Context $StorageContext | Where-Object {$_.CloudTable.Name -eq $TableName}
        if (!($CounterTable)) {
            Write-Verbose "Creating new counter table"
            $CounterTable = New-AzureStorageTable -Name $TableName -Context $StorageContext
        }

        #Updating CounterTable
        $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
        $query.FilterString = "PartitionKey eq 'VmName' and RowKey eq '${RowKey}'"

        $CounterInfo = $CounterTable.CloudTable.ExecuteQuery($query)
        $Etag = $CounterInfo.etag
        if ($CounterInfo -ne $null) {   
            [int]$OLDRowkey = ($CounterInfo).Properties.NewValue.StringValue 
            Write-Verbose "OLDRowkey = ${OLDRowkey}"
            [int]$Rowkey1 = $OLDRowkey +1
            [String]$NewValue = "{0:D4}" -f $Rowkey1
            Write-Verbose "NewValue = ${NewValue}"
            $entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity 'VmName', $RowKey
            $entity2.Properties.Add("NewValue", $NewValue)
            $entity2.ETag = $Etag
            try {
                $result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Replace($entity2))    
                if ($result.HttpStatusCode -eq "204") {
                    Write-Verbose "Updated table"
                    $UpdateSuccess = $true
                    $VmName = "${RowKey}${NewValue}"
                    $CounterBasedVmName = $VmName
                }
            } catch {
                Write-Verbose "ERROR updating table"
                # Conflict Error expected
            }
        } else {  
            $NewValue = "0001" 
            Write-Verbose "Cannot find ${RowKey} - creating new entry with value ${NewValue}"
            $entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity 'VmName', $RowKey
            $entity2.Properties.Add("NewValue", $NewValue)
            $entity2.ETag = $Etag
            $ErrorActionPreference = "SilentlyContinue"
            $result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Insert($entity2)) 
            if ($result.HttpStatusCode -eq "204") {
                Write-Verbose "Updated table"
                $UpdateSuccess = $true
                $VmName = "${RowKey}${NewValue}"
                $CounterBasedVmName = $VmName
            } else {
                Write-Verbose "ERROR updating table"
            }
            $ErrorActionPreference = "Stop"
        }
    } until (($UpdateSuccess -eq $true) -or ($UpdateCounter -gt 100))

    Write-Verbose "Retrieved VMNAME first Loop: $VmName"

    $VmExits = $true
    While ($VmExits) {
        forEach ($Subscription in $Runbook.Configuration.Subscriptions) {
            $Conn = Get-AutomationConnection -Name $Subscription.ConnectionAssetName
            $AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint 
            #The service principal used for logging in to the customer subscription could have permissions for many subscriptions. After switching to the customer subscription always explicitly select the specified subscription specified in the input parameter. 
            $Result = Select-AzureRmSubscription -SubscriptionId $Subscription.Id
            Write-Verbose "Connected to customer subscription: $($Result.Subscription.SubscriptionName)"
            Write-Verbose "Looking for VM: ${VmName}"
            $Vmcheck = Get-AzureRmVM | Where-Object {$_.name -like "$VmName"}
            if ($Vmcheck -ne $null) {
                $VmExits = $true
                break;
            } else {
                $VmExits = $false
            }
        }

        if ($VmExits) {
            Write-Verbose "VM already exists - incrementing counter"
            #Increment VM sequence number
            $StrNum = $VmName.SubString($VmName.Length-4, 4)
            [int]$num = $VmName.SubString($VmName.Length-4, 4) 
            $newcount = $num + 1
            [String]$NewValue = "{0:D4}" -f $newcount 
            $VmName = $VMName.Replace($StrNum, $NewValue) 
        }
    }

    if ($CounterBasedVmName -ne $VmName) {
        # Login to default connection for updating the counter value because VM(s) where found with identical counter value
        $Conn = Get-AutomationConnection -Name DefaultRunAsConnection
        $AddAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
        $UpdateCounter = 0
        $UpdateSuccess = $False
        do {
            $UpdateCounter++
            $CounterTable = Get-AzureStorageTable -Context $StorageContext | Where-Object {$_.CloudTable.Name -eq $TableName}
            if (!($CounterTable)) {
                $CounterTable = New-AzureStorageTable -Name $TableName -Context $StorageContext
            }

            #Updating CounterTable
            $query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
            $Query.FilterString = "PartitionKey eq '$($RowKey)'"

            $CounterInfo = $CounterTable.CloudTable.ExecuteQuery($query)
            $Etag = $CounterInfo.etag
            if ($CounterInfo -ne $null) {  
                $entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity $RowKey,""
                $entity2.Properties.Add("NewValue", $NewValue)
                $entity2.ETag = $Etag
                try {
                    $result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Replace($entity2))    
                    if ($result.HttpStatusCode -eq "204") {
                        $UpdateSuccess = $true
                        $VmName = $RowKey + $NewValue
                        $CounterBasedVmName = $VmName
                    }
                } catch {
                    # Conflict Error expected
                }
            }
        } until(($UpdateSuccess -eq $true) -or ($UpdateCounter -gt 100))
    }
    
    Write-Output "VM: $VmName"
} catch {
    Write-Output "FAILURE"
    Write-Output $_.ToString()
}   