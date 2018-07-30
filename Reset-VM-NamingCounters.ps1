#Requires -Modules Atos.RunbookAutomation
<#
    .SYNOPSIS
    This script Reset VM Naming counter in Storage Table.
    
    .INPUTS
    $VirtualMachineNameCode - Specifies the Character code like ivm,sql
    
    .OUTPUTS
    Displays processes step by step during execution
    
    .NOTES
    Author:     Abhijit Kakade
    Company:    ATOS
    Email:      abhijit.kakade@atos.net
    Created:    2017-07-26
    Updated:    2017-07-26
    Version:    1.1
    
    .Note 
    Enable the Log verbose records of runbook
#>

param(
#The name code for a VM
[Parameter(Mandatory=$true)] 
[String] 
$VirtualMachineNameCode

)

try {
    #Input Validation
    if ([string]::IsNullOrEmpty($VirtualMachineNameCode)) {throw "Input parameter VirtualMachineNameCode missing"} 
    
    #Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription
	
    Write-Verbose "Retrieve runbook objects"
    #Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)
    
    if ($VirtualMachineNameCode.Length -gt 3) {
        throw "Number of character in VirtualMachineNameCode '${VirtualMachineNameCode}' exceeds the maximum size of 3."
	}
	
    $VmNameCodeCheck = $Runbook.Configuration.VirtualMachine.Names | Where-Object {$_.Code -eq $VirtualMachineNameCode}
    Write-Verbose "VmNameCodeCheck = ${VmNameCodeCheck}"
    if (!$VmNameCodeCheck) {
        throw "Namecode: ${VirtualMachineNameCode} not valid!"
	}
	
    $TableName = $Runbook.Configuration.Customer.NamingConventionSectionA + "vmcountertable"
    Write-Verbose "TableName = ${TableName}"
	
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $Runbook.StorageAccount -StorageAccountKey $StorageAccountKey[0].Value
    $VmCounter = ""
    $UpdateCounter = 0
    $UpdateSuccess = $False
	
    do {
        $UpdateCounter++
        Write-Verbose "UpdateCounter = ${UpdateCounter}"
        $CounterTable = Get-AzureStorageTable -Context $StorageContext | Where-Object {$_.CloudTable.Name -eq $TableName}

        if (!($CounterTable)) {			
		    #Ignore there is no table yet available because then a reset of counter is not needed.
			$UpdateSuccess = $true      
			$status = "SUCCESS"       
		}
		else {
			#Updating CounterTable
			$query = New-Object "Microsoft.WindowsAzure.Storage.Table.TableQuery"
			$query.FilterString = "PartitionKey eq 'VmName'"
			$CounterInfo = $CounterTable.CloudTable.ExecuteQuery($query)
			$Etag = $CounterInfo.etag
		
			#Check if Query Result is null 
			if ($CounterInfo -ne $null) {   
			
				$VMcodeExpression = "*" + $VirtualMachineNameCode + "*"
			
				foreach($CIRecord in $CounterInfo)
				{
				
					#Compare if selected Record's RowKey contain VMNamecode                
					if ($CIRecord.RowKey -like $VMcodeExpression )
					{
						#$CIRecord.RowKey
						[String]$NewValue = "{0:D4}" -f "0000"
						$RowKey = $CIRecord.RowKey
					
						Write-Verbose "NewValue = ${NewValue}"
						$entity2 = New-Object -TypeName Microsoft.WindowsAzure.Storage.Table.DynamicTableEntity 'VmName', $RowKey
						$entity2.Properties.Add("NewValue", $NewValue)
						$entity2.ETag = $CIRecord.Etag
					
						try {
							$result = $CounterTable.CloudTable.Execute([Microsoft.WindowsAzure.Storage.Table.TableOperation]::Replace($entity2))    
							if ($result.HttpStatusCode -eq "204") {
								$UpdateSuccess = $true
								$status = "SUCCESS";
							}
							} catch {
							Write-Verbose "ERROR updating table"
							$status = "FAILURE"
							#Conflict Error expected
						}
					} 
					#Selected Record's RowKey do not contain VMNamecode 
					else
					{
						Write-Verbose "No records with VirtualMachineNameCode = ${VirtualMachineNameCode}"
					    #Ignore there is no record yet available because then a reset of counter is not needed.
						$UpdateSuccess = $true      
						$status = "SUCCESS"       
					} 
					#End ForEach
				}
			}
			else {  
				#If Table dont have records
				Write-Verbose "No records with 'VmName'"
				$status = "SUCCESS"
				$UpdateSuccess = $true
			}
		}
	} until (($UpdateSuccess -eq $true) -or ($UpdateCounter -gt 100))

	Write-Output $status
} 
catch {
	$status = "FAILURE"
	$ReturnMessage = $_.ToString()
	
	Write-Output $status
	Write-Output $ReturnMessage
}

