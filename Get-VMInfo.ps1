#Requires -Modules Atos.RunbookAutomation
#Requires -Version 5.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Script getting details of virtual machines on customer subscription

.DESCRIPTION
    This script gets details of virtual machines per customer subscription with VM Name, CPU, Memory and Storage
    To be run on Hybrid Runbook Worker only

.INPUTS
    
.OUTPUTS
    CSV file with details of virtual machines. The file will also be exported to storage account in the same resource group as the automation account

.EXAMPLE
    .\Get-VMInfo.ps1

.NOTES
                          
    Author: Brijesh Shah     
    Company: Atos
    Email: brijesh.shah@atos.net
    Created: 07 September 2017
    Version: 1.0
#>

try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    $ContainerName = "reports"
    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")

    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.Name -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $Runbook.ResourceGroup -Name $Runbook.StorageAccount
    $StorageContext = New-AzureStorageContext -StorageAccountName $($Runbook.StorageAccount) -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue 
    if($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Output -Message "Container does not exist. Creating new Container $ContainerName for reporting..."
    }

    if(-not (Test-Path -Path "C:\VMInfo"))
    {
        Write-Output "Creating new temporary directory for updating file..."
        New-Item -ItemType Directory -Path "C:\VMInfo" | Out-Null
        Write-Output "Directory created"
    }

    $CurrentDateAndTime = ([datetime]::Now).Date
    $StartDateAndTime = $CurrentDateAndTime.AddDays(-1)
    $CurrentDate = Get-Date -Date $StartDateAndTime -Format u

    $count=1
    
    foreach($SubscriptionID in $SubscriptionIDs)
    {
    Get-AzureStorageBlobContent -Blob "VMInfo_sub$($count).csv" -Container "$ContainerName" -Context $StorageContext -Destination "C:\VMInfo\VMInfo_sub$($count).csv" -Force -ErrorAction SilentlyContinue 
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionID -Connections $Runbook.Connections
    Write-Output -InputObject "Connect to customer subscription"
    Set-AzureRmContext -SubscriptionId "$SubscriptionID"

    $rmvms=Get-AzureRmVM
    $vmarray1 = @()
    foreach ($vm in $rmvms) 
        {     
            $Properties = @{
                Name=$vm.Name
                Location=$vm.Location
                VmSize=$vm.HardwareProfile.VmSize
                OsDiskSizeGB=$vm.StorageProfile.OsDisk.DiskSizeGB
                #DataDisksSizeGB=$vm.StorageProfile.DataDisks.DiskSizeGB
                NumberOfDatadisks=$vm.StorageProfile.DataDisks.Count
                CurrentDate = $CurrentDate
                }
            $vmarray1 += New-Object psobject -Property $Properties
        }
    Write-Output $vmarray1 | Format-Table
    $vmarray1 | Export-Csv -Path "C:\VMInfo\vmarray1.csv" -Force -NoTypeInformation

    $vmarray2 = @()
    foreach($loc in ($vmarray1 | ForEach-Object {$_.Location} | Select-Object -Unique))
    {
        $CoresRAM = Get-AzureRmVMSize -Location $loc
        foreach ($vmsize in ($vmarray1 | ForEach-Object {$_.VmSize} | Select-Object -Unique))
        {
            $vmarray2 += $CoresRAM | Where-Object {($_.Name -eq $vmsize)} | Select-Object @{Label='VmSize';Expression={$_.Name}}, @{Label='Cores';Expression={$_.NumberOfCores}},@{Label='RAM';Expression={$_.MemoryInMB}}
        }
    }
    Write-Output $vmarray2
    $vmarray2 | Export-Csv -Path "C:\VMInfo\vmarray2.csv" -Force -NoTypeInformation

    $VMCores = @{}
    Import-Csv 'C:\VMInfo\vmarray2.csv' | ForEach-Object {
      ($VMCores[$_.VmSize] = $_.Cores)
    }

    $VMRAM = @{}
    Import-Csv 'C:\VMInfo\vmarray2.csv' | ForEach-Object {
      ($VMRAM[$_.VmSize] = $_.RAM)
    }

    Import-Csv 'C:\VMInfo\vmarray1.csv' |
      Select-Object -Property CurrentDate, Name, OsDiskSizeGB, NumberOfDatadisks, @{Label='Cores';Expression={$VMCores[$_.VmSize]}},@{Label='RAM';Expression={$VMRAM[$_.VmSize]}} | Export-Csv -Path "C:\VMInfo\VMInfo_sub$($count).csv" -Delimiter ',' -NoType -Append
    
    $count++
}
    $ManagementContext = Connect-AtosManagementSubscription

    If ($null -eq $ContainerTest)
    {
        Write-Verbose -Message "Couldn't find container. Creating new container $ContainerName..."
        New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission Blob | Out-Null
    }
    else
    {
        Write-Verbose -Message "Reporting Container already exists."
    }
    
    $count = 1
    foreach($SubscriptionID in $SubscriptionIDs)
    {
        Set-AzureStorageBlobContent -Context $StorageContext -Container $ContainerName -Blob "VMInfo_sub$($count).csv" -File "C:\VMInfo\VMInfo_sub$($count).csv" -Force  | Out-Null
        $count++
    }
    Write-Output -InputObject "Files updated in storage account."
    Remove-Item -Path "C:\VMInfo\*.csv" -Force -Recurse
}
catch
{
    throw "$_"
}