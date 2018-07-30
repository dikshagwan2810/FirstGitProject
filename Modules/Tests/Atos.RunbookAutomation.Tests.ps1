# https://johnlouros.com/blog/unit-testing-in-powershell
# always use '-Force' to load the latest version of the module
Import-Module '..\Atos.RunbookAutomation.psm1'   -Force
Import-Module AzureRM.Profile

Describe "Unit Tests" {
    InModuleScope Atos.RunbookAutomation {
        # arrange
        Mock Get-AutomationConnection -ModuleName 'Atos.RunbookAutomation'  -MockWith { return @{"SubscriptionId" = (new-guid); "ApplicationId" = (new-guid); "TenantId" = (new-guid); "CertificateThumbprint" = 'EED589BC9451FBAEFEE0CAA8D4AF6D3BBB2529C6'} } 
   
        $AZProfile = [Microsoft.Azure.Commands.Profile.Models.PSAzureProfile]::new()
        $AZProfile.Context = [Microsoft.Azure.Commands.Profile.Models.PSAzureContext]::new()
        $AZProfile.Context.Tenant = [Microsoft.Azure.Commands.Profile.Models.PSAzureTenant]::new()
        $AZProfile.Context.Account = [Microsoft.Azure.Commands.Profile.Models.PSAzureRMAccount]::new()
        $AZProfile.Context.Subscription = [Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription]::new()

        Mock Add-AzureRMAccount -ModuleName 'Atos.RunbookAutomation' { return $AZProfile }
          
        Context "Connect-AtosManagementSubscription - Check internal call logic" {
            # act

            It "Should call Get-AutomationConnection ONCE" {

                Connect-AtosManagementSubscription

                # assert
                Assert-MockCalled Get-AutomationConnection -Exactly 1
            }   
        

            It "Should call Write-Verbose TWICE" {
                Mock Write-Verbose {}

                Connect-AtosManagementSubscription

                # assert
                Assert-MockCalled Write-Verbose -Exactly 2
      
            }
        }
      
        Context "Connect-AtosManagementSubscription - Output processing" {

            It "Should return a PSAzureContext" {

                Connect-AtosManagementSubscription | Should BeOfType [Microsoft.Azure.Commands.Profile.Models.PSAzureContext]
            }
        }

        Context "Connect-AtosCustomerSubscription - Input processing" {

            $subscriptionId = (new-guid)
                            
            It "Should throw on Subscription id not found" {
            
                { Connect-AtosCustomerSubscription -SubscriptionID $subscriptionId  -Connections ([psobject]::new(@{(New-Guid) = 'Test'})) } | Should throw "Subscription '$SubscriptionId' not found in RunAsConnectionRepository."
            }

            It "Should throw on AutomationConnection name not found" {

                Mock Get-AutomationConnection {}

                { Connect-AtosCustomerSubscription -SubscriptionID $subscriptionId  -Connections  [System.Collections.Hashtable]::new(@{$subscriptionId = 'Test'}) } | should throw 

            }

            It "Should throw 'Subscription 'UNKNOWN' not found in RunAsConnectionRepository." {

                { Connect-AtosCustomerSubscription -SubscriptionID 'UNKNOWN' -Connections @{"$subscriptionId" = 'test'} } |  Should throw "Subscription 'UNKNOWN' not found in RunAsConnectionRepository."
            }

            It "Should throw 'Failed to activate subscription ${SubscriptionId} after 5 attempts'" {

                $AZProfile.Context.Subscription.SubscriptionId = '00000000-0000-0000-0000-000000000000'

                $AZProfile.Context.Subscription.SubscriptionName = 'test'

                Mock Get-AutomationConnection { return @{id = '0' ; TenantId = '0'; ApplicationId = '0'; CertificateThumbprint = '0'} }

                Mock Select-AzureRmSubscription { return $AZProfile.Context }

                Mock Get-AzureRmContext { return $AZProfile.Context }

                Mock Start-Sleep { }

                { Connect-AtosCustomerSubscription -SubscriptionID ${SubscriptionId} -Connections @{"$subscriptionId" = 'test'} } |  Should throw "Failed to activate subscription ${SubscriptionId} after 5 attempts"
            }

            
        }

        Context "Connect-AtosCustomerSubscription - Output processing" {

            It "Should return a PSAzureContext" {

                $subscriptionId = (new-guid)

                $AZProfile.Context.Subscription.SubscriptionId = $subscriptionId

                $AZProfile.Context.Subscription.SubscriptionName = 'test'

                Mock Get-AutomationConnection { return @{id = '0' ; TenantId = '0'; ApplicationId = '0'; CertificateThumbprint = '0'} }
                
                #Mock Select-AzureRmSubscription { return  @{Context = @{Subscription = $subscriptionId}} }

                #Mock Get-AzureRmContext { return @{Subscription = @{SubscriptionId = $subscriptionId}} }

                Mock Select-AzureRmSubscription { return $AZProfile.Context }

                Mock Get-AzureRmContext { return $AZProfile.Context }

                Mock Start-Sleep { }

                Connect-AtosCustomerSubscription -SubscriptionID $subscriptionId -Connections @{"$subscriptionId" = 'test'} |  Should BeOfType [Microsoft.Azure.Commands.Profile.Models.PSAzureContext]

            }
        }

        Context "Set-SnowVmPowerStatus" {

            It "Checks input parameter handlers" {}
            It "Checks basic internal logic" {}
            It "Checks return type" {}

        }
    }
}

Describe "Integration Tests" {
    InModuleScope Atos.RunbookAutomation {
        InModuleScope Atos.RunbookAutomation {
            # # arrange
            # Mock Get-AutomationConnection -ModuleName 'Atos.RunbookAutomation'  -MockWith { return @{"SubscriptionId" = (new-guid); "ApplicationId" = (new-guid); "TenantId" = (new-guid); "CertificateThumbprint" = 'EED589BC9451FBAEFEE0CAA8D4AF6D3BBB2529C6'} } 
   
            # $AZProfile = [Microsoft.Azure.Commands.Profile.Models.PSAzureProfile]::new()
            # $AZProfile.Context = [Microsoft.Azure.Commands.Profile.Models.PSAzureContext]::new()
            # $AZProfile.Context.Tenant = [Microsoft.Azure.Commands.Profile.Models.PSAzureTenant]::new()
            # $AZProfile.Context.Account = [Microsoft.Azure.Commands.Profile.Models.PSAzureRMAccount]::new()
            # $AZProfile.Context.Subscription = [Microsoft.Azure.Commands.Profile.Models.PSAzureSubscription]::new()

            # Mock Add-AzureRMAccount -ModuleName 'Atos.RunbookAutomation' { return $AZProfile }
        }
    }
}