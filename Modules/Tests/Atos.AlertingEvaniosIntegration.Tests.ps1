# always use '-Force' to load the latest version of the module

Remove-Module -Force -ErrorAction SilentlyContinue Atos.AlertingEvaniosIntegration
Import-Module '..\Atos.AlertingEvaniosIntegration\Atos.AlertingEvaniosIntegration.psm1' -Force

Describe "mpca.public.runbooks.monitoring.AlertingEvaniosIntegration.UnitTests" {
    InModuleScope Atos.AlertingEvaniosIntegration {
        # arrange
        mock Write-Warning {}
        Context "Get-MPCAEvaniosAlertArrayObject" {
            # act
            It "emptyAlertNameInput.throwException" {
                $params = @{
                    AlertRuleName = ""
                    OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                    SeverityNumber = 2
                    RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
                }
                {Get-MPCAEvaniosAlertArrayObject @params} | Should throw "Cannot validate argument on parameter"
            }
            It "invalidWorkspaceIDInput.throwException" {
                $params = @{
                    AlertRuleName = "This is a test alert"
                    OMSWorkspaceID = "XX-BAD-ID-XX"
                    SeverityNumber = 2
                    RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
                }
                {Get-MPCAEvaniosAlertArrayObject @params} | Should throw "Cannot validate argument on parameter"
            }
            It "invalidArrayObjInput.isFalse" {
                $params = @{
                    AlertRuleName = "This is a test alert"
                    OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                    SeverityNumber = 2
                    RowData = @("notaHashTable")
                }
                Get-MPCAEvaniosAlertArrayObject @params | Should Be $false                
            }            
        }
        Context "Get-MPCAEvaniosAlertArrayObject" {
            It "output.isValidType" {
                $params = @{
                    AlertRuleName = "This is a test alert"
                    OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                    SeverityNumber = 2
                    RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
                }
                Get-MPCAEvaniosAlertArrayObject @params | Should BeOfType System.Collections.Hashtable
            } 
            It "output.isValidContent" {
                $params = @{
                    AlertRuleName = "This is a test alert"
                    OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                    SeverityNumber = 2
                    RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
                }
                $table = Get-MPCAEvaniosAlertArrayObject @params
                $table.AlertRuleName | Should Be $params.AlertRuleName
                $table.WorkspaceId  | Should Be $params.OMSWorkspaceID
                $table.Description | Should Be 2
                $table.ResultCount | Should Be 1
                $table.SearchResult | Should BeOfType System.Collections.Hashtable
                $table.SearchResult.tables.count | Should Be 1
                $table.SearchResult.tables[0].name | Should Be "PrimaryResult"
                $table.SearchResult.tables[0] | Should BeOfType System.Collections.Hashtable
                $table.SearchResult.tables[0].rows[0].count | Should Be 2
                $table.SearchResult.tables[0].columns.name.count | Should Be 2 
            }             

        }
        Context "Send-MPCAEvaniosAlert" {
            # prepare a valid alert data object to pass to the function
            $params = @{
                AlertRuleName = "This is a test alert"
                OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                SeverityNumber = 2
                RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
            }
            $AlertDataObj = Get-MPCAEvaniosAlertArrayObject @params
            It "invalidDataObjInput.isFalse" {
                $params = @{
                    AlertDataObj = @{"invalidTableName"="invalidData"}
                    WebhookURI = "https://atosglobaldev.service-now.com/oms2.do"
                }
                Send-MPCAEvaniosAlert @params | Should Be $false                  
            }            
            It "invalidWebhookURIInput.throwException" {
                $params = @{
                    AlertDataObj = $AlertDataObj
                    WebhookURI = "InvalidUrl"
                }
                {Send-MPCAEvaniosAlert @params }| Should throw "Cannot validate argument on parameter"
            }
        }
        Context "Send-MPCAEvaniosAlert" {
            mock Invoke-RestMethod {}            
            # prepare a valid alert data object to pass to the function
            $params = @{
                AlertRuleName = "This is a test alert"
                OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                SeverityNumber = 2
                RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
            }
            $AlertDataObj = Get-MPCAEvaniosAlertArrayObject @params
            It "return.isTrue" {
                $params = @{
                    AlertDataObj = $AlertDataObj
                    WebhookURI = "https://atosglobaldev.service-now.com/oms2.do"
                }                
                Send-MPCAEvaniosAlert @params | Should Be $true  
            }     
            Assert-MockCalled Invoke-RestMethod -Exactly 1    
        }      
        Context "Send-MPCAEvaniosAlert" {
            # prepare a valid alert data object to pass to the function
            $params = @{
                AlertRuleName = "This is a test alert"
                OMSWorkspaceID = "00000000-0000-0000-0000-000000000001"
                SeverityNumber = 2
                RowData = @(@{"Computer"="VM12345"};@{"Error_message"="This is a sample alert message data"})
            }
            $AlertDataObj = Get-MPCAEvaniosAlertArrayObject @params
            It "invalidWebhookURIInput.throwException" {
                $params = @{
                    AlertDataObj = $AlertDataObj
                    WebhookURI = "https://invalidWebhookURI"
                }
                Send-MPCAEvaniosAlert @params | Should Be $false
            }                 
        }             
    }
}

Describe "mpca.public.runbooks.monitoring.AlertingEvaniosIntegration.IntegrationTests" {
    Context "jsonFormat.isValid" {
        It "JSON" {
            Get-MPCASampleOMSAlertJSONPayloadFromRESTAPI | Should Be '{"tables":[{"name":"PrimaryResult","columns":[{"name":"SampleColumn","type":"string"}],"rows":[["SampleData"]]}]}'
        }        
    }
}
