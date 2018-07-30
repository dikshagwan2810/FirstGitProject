#Requires -Version 5.0
#Requires -RunAsAdministrator
#Requires -Modules Atos.RunbookAutomation
#Requires -Modules AzureRm.OperationalInsights

<#
.SYNOPSIS
    Script to get saved search query results from workspace in Azure

.DESCRIPTION
    This script collects results for saved search queries from OMS workspace in the specified subscription and resource group.
    It creates csv file for each query and updates the files in storage account with the results
    Create a schedule on the script to be run daily and provide all the mandatory parameters to the script.
    To be run on Hybrid Runbook Worker only

.INPUTS

.OUTPUTS
    CSV file for every saved search query

.EXAMPLE
    .\Get-OmsSearchQueryResults.ps1

.NOTES

    Author: Austin Palakunnel, Brijesh Shah     
    Company: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 16 May 2017
    Version: 1.0
#>

try
{
    $ManagementContext = Connect-AtosManagementSubscription
    $Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    $ContainerName = "reports"

    $MPCAConfiguration = @{}
    $MPCAConfiguration = (Get-AzureRmAutomationVariable -Name "MPCAConfiguration" -AutomationAccountName $Runbook.AutomationAccount -ResourceGroupName $Runbook.ResourceGroup).Value
    $MPCAConfigurationVar =  ConvertFrom-Json -InputObject $MPCAConfiguration

    $Subscriptions = $Runbook.Configuration.Subscriptions
    $SubscriptionIDs = $Subscriptions.Id.split(":")

    $StorageAccount = Get-AzureRmStorageAccount | Where-Object -FilterScript {$_.StorageAccountName -like $Runbook.StorageAccount -and $_.ResourceGroupName -like $Runbook.ResourceGroup}
    $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName -Name $StorageAccount.StorageAccountName
    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $StorageAccountKey[0].Value
    $ContainerTest = Get-AzureStorageContainer -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue
    If ($null -eq $ContainerTest)
    {
        New-AzureStorageContainer -Name "$ContainerName" -Context $StorageContext -Permission Blob 
        Write-Output "Container does not exist. Creating new Container $ContainerName for reporting..."
    }
    $count=1
    foreach ($SubscriptionId in $SubscriptionIDs)
    {
        if(-not (Test-Path -Path "C:\TempOMSFiles\omsresults_sub$($count)"))
        {
            Write-Output "Creating new temporary directory for updating file..."
            New-Item -ItemType Directory -Path "C:\TempOMSFiles\omsresults_sub$($count)" | Out-Null
            Write-Output "Directory created"
        }
        else
        {
            Write-Output "Clearing old files from directory"
            Get-ChildItem -Path "C:\TempOMSFiles\omsresults_sub$($count)" -Recurse -Force | Remove-Item -Force 
        }
        $count++
    }
    
    # OMS Static Queries
    $QueriesDetail=@()
    $QueriesDetail = @(
        [pscustomobject]@{ "FileName" = "Alerts - Count by alert name.csv";
        "Query" = 'Type=Alert SourceSystem=OMS | select AlertSeverity, AlertName, Computer'
        },
        [pscustomobject]@{ "FileName" = "Alerts - Critical alerts raised which are still active.csv";
        "Query" = 'Type=Alert (AlertSeverity=Error or AlertSeverity=Critical) AlertState!=Closed | measure count() As Count by AlertName'
        },
        [pscustomobject]@{ "FileName" = "Memory - % Committed Bytes in Use.csv";
        "Query" = 'Type=Perf (ObjectName=Memory) (CounterName="% Committed Bytes In Use") | measure Avg(CounterValue) as AvgCommittedBytesInUse, Min(CounterValue) as MinCommittedBytesInUse, Max(CounterValue) as MaxCommittedBytesInUse by Computer'
        },
        [pscustomobject]@{ "FileName" = "Memory - Available Mbytes.csv";
        "Query" = 'Type=Perf ObjectName=Memory CounterName="Available MBytes" | measure Avg(CounterValue) as AvgAvailableMBytes, Min(CounterValue) as MinAvailableMBytes, Max(CounterValue) as MaxAvailableMBytes by Computer'
        },
        [pscustomobject]@{ "FileName" = "Storage - %Free Space.csv";
        "Query" = 'Type=Perf (ObjectName=LogicalDisk) (CounterName="% Free Space") (InstanceName="C:") | measure Avg(CounterValue) as AvgFreeSpace, Min(CounterValue) as MinFreeSpace, Max(CounterValue) as MaxFreeSpace by Computer'
        },
        [pscustomobject]@{ "FileName" = "CPU - %Processor Time.csv";
        "Query" = 'Type=Perf (ObjectName=Processor) CounterName="% Processor Time" (InstanceName="_Total") | measure Avg(CounterValue) as AvgProcessorTime, Min(CounterValue) as MinProcessorTime, Max(CounterValue) as MaxProcessorTime by Computer'
        },
        [pscustomobject]@{ "FileName" = "Changes - All WindowsServices Configuration Changes.csv";
        "Query" = 'Type=ConfigurationChange ConfigChangeType=WindowsServices'
        },
        [pscustomobject]@{ "FileName" = "Changes - All Software Configuration Changes.csv";
        "Query" = 'Type=ConfigurationChange ConfigChangeType=Software'
        },
        [pscustomobject]@{ "FileName" = "Service Availability - Unresponsive agents based on OMS agent.csv";
        "Query" = 'Type=Heartbeat | measure max(TimeGenerated) as LastCall by Computer'
        },
        [pscustomobject]@{ "FileName" = "Update - Computers with automatic update disabled.csv";
        "Query" = 'Type=UpdateSummary WindowsUpdateSetting="Manual" | select WindowsUpdateSetting, Computer, OsVersion'
        },
        [pscustomobject]@{ "FileName" = "Update - All windows computers with missing updates.csv";
        "Query" = 'Type=Update OSType!=Linux UpdateState=Needed Optional=false'
        },
        [pscustomobject]@{ "FileName" = "Update - All windows computers with missing critical or security updates.csv";
        "Query" = 'Type=Update OSType!=Linux UpdateState=Needed Optional=false (Classification="Security Updates" OR Classification="Critical Updates")'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Devices with Signatures out of date.csv";
        "Query" = 'Type=ProtectionStatus | measure max(ProtectionStatusRank) as Rank by DeviceName | where Rank=250'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Protection Status updates.csv";
        "Query" = 'Type=ProtectionStatus | Measure count(ScanDate) by ThreatStatus, ProtectionStatusRank'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Malware detected grouped by threat.csv";
        "Query" = 'Type=ProtectionStatus NOT ((ThreatStatus="No threats detected") OR (ThreatStatus="Unknown"))'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Computers with detected threats.csv";
        "Query" = 'Type=ProtectionStatus ThreatStatusRank > 199 ThreatStatusRank != 470'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Computers with insufficient protection.csv";
        "Query" = 'Type=ProtectionStatus ProtectionStatusRank > 199 ProtectionStatusRank != 550 | measure max(ProtectionStatusRank) as Rank by Computer'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Computers not reporting protection status.csv";
        "Query" = 'Type=ProtectionStatus ProtectionStatusRank !=150 ProtectionStatusRank != 550 | measure max(ProtectionStatusRank) as Rank by Computer | where Rank = 450'
        },
        [pscustomobject]@{ "FileName" = "Malware Assessment - Number of computers with Microsoft antimalware protection.csv";
        "Query" = 'Type=ProtectionStatus TypeofProtection = "Malicious Software Removal Tool" OR TypeofProtection = "System Center Endpoint Protection" | measure countdistinct(Computer) by TypeofProtection'
        },
        [pscustomobject]@{ "FileName" = "Activity - Failed Azure Activity Status.csv";
        "Query" = 'Type=AzureActivity ActivityStatus=Failed | select OperationName, Caller, Category, Resource'
        },
        [pscustomobject]@{ "FileName" = "Events - Computers with EventLog errors.csv";
        "Query" = 'Type=Event EventLevelName=error | select Computer, Source, EventLog, EventID, RenderedDescription'
        },
        [pscustomobject]@{ "FileName" = "SQL - Assessment Recommendation failed.csv";
        "Query" = 'Type=SQLAssessmentRecommendation RecommendationResult=Failed | select Recommendation, Description, FocusArea, Computer, AffectedObjectType, AffectedObjectName'
        },
        [pscustomobject]@{ "FileName" = "Identity and Access - Failed logons by computer.csv";
        "Query" = 'Type=SecurityEvent EventID=4625 | select Account, Computer, Activity'
        },
        [pscustomobject]@{ "FileName" = "Identity and Access - Logon Activity by Account.csv";
        "Query" = 'Type=SecurityEvent EventID=4624 | select Account, Computer, Activity'
        },
        [pscustomobject]@{ "FileName" = "Identity and Access - SecurityEvents Schedule.csv";
        "Query" = '* | measure Count() by Type'
        },
        [pscustomobject]@{ "FileName" = "VM Overview - Display guest OS of the VM.csv";
        "Query" = 'Type=SecurityBaseline | select Computer, OSName'
        },
        [pscustomobject]@{ "FileName" = "VM Overview - Display Ipaddress of the VM.csv";
        "Query" = 'Type=ProtectionStatus | select Computer, ComputerIP_Hidden'
        },
        [pscustomobject]@{ "FileName" = "VM Overview - Display Disk Writes per sec throughput IOPS of the VM.csv";
        "Query" = 'Type=Perf ObjectName=LogicalDisk (CounterName="Disk Writes/sec") InstanceName=_Total | Measure Avg(CounterValue) as AvgIOPS, Min(CounterValue) as MinIOPS, Max(CounterValue) as MaxIOPS by Computer'
        }
    )

    $count=1
    foreach($SubscriptionID in $SubscriptionIDs)
    {
        foreach($Query in $QueriesDetail)
        {
            Get-AzureStorageBlobContent -Blob "omsresults_sub$($count)\$($Query.FileName)" -Container "$ContainerName" -Context $StorageContext -Destination "C:\TempOMSFiles\omsresults_sub$($count)\$($Query.FileName)" -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionID -Connections $Runbook.Connections
        Write-Output "Connect to customer subscription"
        $CustomerContext = Set-AzureRmContext -SubscriptionId "$SubscriptionID"       

        $MPCASubId = $MPCAConfigurationVar.MPCAConfiguration.Subscriptions | where {$_.Id -like $SubscriptionID}
        $OMSWorkspace = $MPCASubId.OMSWorkspaceName
        foreach($OMSWorkspaceName1 in $OMSWorkspace)
        {
            $WorkspaceName = Get-AzureRmOperationalInsightsWorkspace | Where-Object {$_.Name -eq $OMSWorkspaceName1}
            $ResourceGroupName = $WorkspaceName.ResourceGroupName
        }

        # Set query start search time to rounded 1 day interval start time
        $CurrentDateAndTime = [datetime]::Now    
                
        $EndDateAndTime = $CurrentDateAndTime.Date
        $StartDateAndTime = $EndDateAndTime.AddDays(-1)

        $EndDate = Get-Date -Date $EndDateAndTime -Format u    
        $StartDate = Get-Date -Date $StartDateAndTime -Format u
    
        $TenantId = $CustomerContext.Tenant.Id
        if($null -eq $TenantId)
        {
            $TenantId = $CustomerContext.Tenant.TenantId
        }

        # Execute Instance queries and save file to the local machine
        foreach($Query in $QueriesDetail)
        {
            $Results = @{}
            $outfilename = "C:\TempOMSFiles\omsresults_sub$($count)\$($Query.FileName)"
            $Results = Get-AzureRmOperationalInsightsSearchResults -ResourceGroupName $ResourceGroupName -WorkspaceName $OMSWorkspace -Query $Query.Query -Start $StartDateAndTime -End $EndDateAndTime -Top 15000
            
            $CSV = @()
            foreach($Result in $Results.Value)
            {
                $CSV += $($Result.ToString() | ConvertFrom-Json)
            }
            foreach($entry in $CSV)
            {
                $entry | Add-Member -MemberType NoteProperty -Name "TenantId" -Value $TenantId -Force
                $entry | Add-Member -MemberType NoteProperty -Name "TimeGenerated" -Value $StartDate -Force
            }
            if($null -ne $CSV)
            {
                $CSV | Export-Csv -Path  $outfilename -Append -NoTypeInformation -Force
            }
        }
        $count++
    }    
    # Upload the local files to storage account
    Write-Output "Uploading files to storage account..."
    $ManagementContext = Connect-AtosManagementSubscription

    $count=1
    foreach($SubscriptionID in $SubscriptionIDs)
    {
        foreach($Query in $QueriesDetail)
        {
            if(Test-Path -Path "C:\TempOMSFiles\omsresults_sub$($count)\$($Query.FileName)")
            {
                Set-AzureStorageBlobContent -Container $ContainerName -Context $StorageContext -File "C:\TempOMSFiles\omsresults_sub$($count)\$($Query.FileName)" -Blob "omsresults_sub$($count)\$($Query.FileName)" -Force | Out-Null
                Remove-Item -Path "C:\TempOMSFiles\omsresults_sub$($count)\*.csv" -Force | Out-Null
            }
        }
        $count++
    }
    Write-Output "Upload complete"  
}
catch
{
    throw "$_"
}