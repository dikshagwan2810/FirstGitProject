Function Get-MPCAEvaniosAlertArrayObject {
    param(
        # The alert rule name is displayed in the incident in ServiceNow
        [Parameter(Mandatory=$true)]
        [ValidateLength(1,128)]
        [String] $AlertRuleName,

        # The OMS workspace ID associated to one of the customer subscription. Used by Evanios to match the customer.
        [Parameter(Mandatory=$true)]
        [ValidateLength(36,36)]
        [String] $OMSWorkspaceID,

        # The severity number of the incident : 1 for Critical (only if customer impacted), 2 for Major (most common), 3 for Minor
        [Parameter(Mandatory=$true)]
        [ValidateRange(1,3)]
        [Int] $SeverityNumber,

        # An array of entries with name and value. Each entry will be shown on a separate line in the incident message text.
        # Each entry must consist of an hash array in the form @{"MyValueName"="MyValue"}.
        [Parameter(Mandatory=$true)]
        [Array] $RowData
    )
    
    # Validate the rowdata array
    If ($RowData.count -lt 1) {
        Write-Warning ("The rowdata array must contains at least one item of type Hash (ColumnName=Value)")
        return $false;
    }
    Foreach ($Row in $RowData) {
        If ($row.GetType().Name -ne "Hashtable") {
            Write-Warning ("The rowdata array must contains only items of type Hash (ColumnName=Value)")
            return $false;
        }
    }    

    # Generate the columns and rows array based on provided rowdata array
    $columns = @()
    $rows = @()
    Foreach ($Row in $RowData) {
        $item = $Row.GetEnumerator() | Select-Object -first 1
        $columns += @{"name"=$item.Name;"type"="String"}
        $rows += $item.Value
    }
    $TableObj = @{
        "name"="PrimaryResult";
        "columns" =  (New-Object System.Collections.ArrayList)
        "rows" =  (New-Object System.Collections.ArrayList)
    }
    $TableObj.Rows.Add($rows) | out-null
    $TableObj.Columns += $columns
    # Generate final object
    $AlertDataObj = @{
        "WorkspaceId" = $OMSWorkspaceID;
        "AlertRuleName" = $AlertRuleName;
        "ResultCount" = 1;
        "Description" = $SeverityNumber
        "SearchResult" = @{"tables" = @($TableObj)}
    }
    return $AlertDataObj

    <#
    .SYNOPSIS
    Generate an array object that will be used to trigger an Alert in Evanios

    .DESCRIPTION
    This is the first function to call when an alert needs to be generated in Evanios.
    This function takes some information on the alert and prepare the array object 
    that will be passed to the second function.
    Even if the alert is not related to OMS,
    the OMS workspace ID is mandatory because it is used by Evanios to link the incident 
    to the correct customer.
    It must be one of the OMS workspace ID linked to a customer subscription.

    .EXAMPLE
    $params = @{
        AlertRuleName = "This is a sample alert sent from runbook Test1"
        OMSWorkspaceID = "7107d820-c410-45f8-b812-1e020b45d976"
        SeverityNumber = 2
        RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
    }
    $AlertDataObj = Get-MPCAEvaniosAlertArrayObject @params

    #>    
 }

Function Send-MPCAEvaniosAlert {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $AlertDataObj,

        [Parameter(Mandatory=$true)]
        [ValidatePattern("^(http|https)://")]
        [PSCustomObject] $WebhookURI
    )
    
    # Validate the data array 
    $MandatoryPropertiesList = @("WorkspaceId","AlertRuleName","ResultCount","Description")
     Foreach ($MandatoryProperty in $MandatoryPropertiesList) {
        If (!$AlertDataObj.$MandatoryProperty) {
            Write-Warning ("The provided alert data array is missing mandatory data ["+$MandatoryProperty+"]")
            return $false;
        }
    }
    If ($AlertDataObj.SearchResult.tables[0].name -ne "PrimaryResult") {
        Write-Warning ("The provided alert data array is missing mandatory data [SearchResult/Tables/PrimaryResult]")
        return $false;
    }
    If ($AlertDataObj.SearchResult.tables[0].columns.count -lt 1) {
        Write-Warning ("The provided alert data array is missing mandatory data [SearchResult/Tables/PrimaryResult/Columns]")
        return $false;
    }
    If ($AlertDataObj.SearchResult.tables[0].rows.count -ne 1) {
        Write-Warning ("The provided alert data array is missing mandatory data [SearchResult/Tables/PrimaryResult/Rows]")
        return $false;
    }
    If ($AlertDataObj.SearchResult.tables[0].Columns.count -ne $AlertDataObj.SearchResult.tables[0].Rows[0].count) {
        Write-Warning ("Number of rows and columns does not match in the provided alert data array ")
        return $false;
    }
    
    # Prepare the JSON payload
    Try {
        $JSONPayload = convertto-json -InputObject $AlertDataObj -Depth 99 -Compress | ForEach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) }
    } catch {
        Write-Warning ("Unable to generate the JSON payload from the alert array provided. Invalid data.")
        return $false
    }

    # Send JSON to SNOW OMS webhook 
    $params = @{
        Headers = @{'accept'='application/json';'Content-Type'='application/json'}
        Body = $JSONPayload
        Method = 'Post'
        ContentType = 'application/json'
        UserAgent = 'OMS-Webhook'
        URI = $WebhookUri
    }

    Try {
        Invoke-RestMethod @params | out-null
    } catch {
        Write-Warning ("Unable to send JSON to SNOW webhook using URI ["+$params["URI"]+"]`n"+$Error[0].Exception.Message)
        return $false
    }
    return $true

    <#
    .SYNOPSIS
    Send an alert to Evanios/SNOW webhook with the provided alert array object 
    
    .DESCRIPTION
    This is the second function to call when an alert needs to be generated in Evanios.
    The provided array object is converted to JSON and sent to the Evanios webhook of the ServiceNow
    instance using the specified URI.
    Details of JSON payload format is specified here :
    https://dev.loganalytics.io/documentation/Using-the-API/ResponseFormat

    .EXAMPLE
    $params = @{
        AlertDataObj = $AlertDataObj
        WebhookURI = "https://atosglobaldev.service-now.com/oms2.do"
    }
    Send-MPCAEvaniosAlert @params    

    #>        
}

function Get-MPCASampleOMSAlertJSONPayloadFromRESTAPI() {
    $oms_restapi_uri = "https://api.loganalytics.io/v1/workspaces/DEMO_WORKSPACE/query"
    $oms_query = 'AzureActivity | take 1 | project SampleColumn="SampleData"'
    $body = @{"query" = $oms_query} | ConvertTo-Json
    $params = @{
        Headers = @{"X-Api-Key" = "DEMO_KEY"}
        Body = $body
        Method = 'Post'
        ContentType = 'application/json'
        Uri = $oms_restapi_uri
    }
    try {
        $response = Invoke-WebRequest @params
    } catch {
        throw "Failed to execute query"
    }
    if ($response.StatusCode -ne 200 -and $response.StatusCode -ne 204) {
        $statusCode = $response.StatusCode
        $reasonPhrase = $response.StatusDescription
        $message = $response.Content
        throw "Failed to execute query.`nStatus Code: $statusCode`nReason: $reasonPhrase`nMessage: $message"
    }
    return $response.Content

    <#
    .SYNOPSIS
    Get the JSON payload of a sample OMS alert using OMS REST API 
    
    .DESCRIPTION
    This function is only used for integration testing,
    to verify that the format used by OMS Alert have not been changed.
    Details of JSON payload format is specified here :
    https://dev.loganalytics.io/documentation/Using-the-API/ResponseFormat

    .EXAMPLE
    $json = Get-MPCASampleOMSAlertJSONPayloadFromRESTAPI
   
    #>       
}

Export-ModuleMember -function "Get-MPCAEvaniosAlertArrayObject"
Export-ModuleMember -function "Send-MPCAEvaniosAlert"
Export-ModuleMember -function "Get-MPCASampleOMSAlertJSONPayloadFromRESTAPI"
