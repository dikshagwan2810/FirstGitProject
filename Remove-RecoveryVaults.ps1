Param (
    # The ID of the subscription to use
    [Parameter(Mandatory=$true)]
    [String][ValidatePattern('[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}')]
    $SubscriptionId,

    [Parameter(Mandatory=$false)]
    [Boolean]
    $OnlyRemoveEmptyVaults = $true
)

# Everything wrapped in a try/catch to ensure SNow-compatible output
try {
    # Connect to the management subscription
    Write-Verbose "Connect to default subscription"
    $ManagementContext = Connect-AtosManagementSubscription

    Write-Verbose "Retrieve runbook objects"
    # Set the $Runbook object to global scope so it's available to all functions
    $global:Runbook = Get-AtosRunbookObjects -RunbookJobId $($PSPrivateMetadata.JobId.Guid)

    # Switch to customer's subscription context
    Write-Verbose "Connect to customer subscription"
    $CustomerContext = Connect-AtosCustomerSubscription -SubscriptionId $SubscriptionId -Connections $Runbook.Connections

    # Code that must be run under the CUSTOMER context goes here
    Write-Verbose "Retrieving all Recovery Services Vaults in this sucscription"
    $Vaults = Get-AzureRmRecoveryServicesVault
    $VaultCount = $Vaults.Count
    $RemovedCount = 0
    $FailedCount = 0
    $IgnoredCount = 0
    $IgnoredVaults = @()
    $RemovedVaults = @()
    $FailedVaults = @()

    forEach ($Vault in $Vaults) {
        Write-Verbose "Processing vault: $($Vault.name)"
        Set-AzureRmRecoveryServicesVaultContext -Vault $Vault
        $Containers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType 'AzureVM' -Status 'Registered'

        if ($Containers.Count -eq 0) {
            Write-Verbose "  Found $($Containers.Count) containers"
            Write-Verbose "  Removing vault"
            $RemoveResults = Remove-AzureRmRecoveryServicesVault -Vault $Vault
            if ($RemoveResults.Response -match 'has been deleted') {
                Write-Verbose "  Success: $($RemoveResults.Response)"
                $RemovedCount++
                $RemovedVaults += $Vault.Name
            } else {
                Write-Verbose "  FAILURE: $($RemoveResults.Response)"
                $FailedCount++
                $FailedVaults += $Vault.Name
            }
        } else {
            if ($OnlyRemoveEmptyVaults -eq $true) {
                Write-Verbose "  The following backup containers exist:"
                forEach ($Container in $Containers) {
                    Write-Verbose "    - $($Container.ResourceGroupName)\$($Container.FriendlyName)"
                }
                Write-Verbose "  Leaving vault in place.  To remove vaults with registered VMs set -OnlyRemoveEmptyVaults to $false"
                $IgnoredCount++
                $IgnoredVaults += $Vault.Name
            } else {
                Write-Verbose "  Removing containers"
                forEach ($Container in $Containers) {
                    Write-Verbose "    Disabling protection for $($Container.ResourceGroupName)\$($Container.FriendlyName)"
                    $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $Container -WorkloadType 'AzureVM'
                    Disable-AzureRmRecoveryServicesBackupProtection -Item $BackupItem -RemoveRecoveryPoints -Confirm:$false -Force
                }

                Write-Verbose "  Removing vault"
                $RemoveResults = Remove-AzureRmRecoveryServicesVault -Vault $Vault
                if ($RemoveResults.Response -match 'has been deleted') {
                    Write-Verbose "  Success: $($RemoveResults.Response)"
                    $RemovedCount++
                    $RemovedVaults += $Vault.Name
                } else {
                    Write-Verbose "  FAILURE: $($RemoveResults.Response)"
                    $FailedCount++
                    $FailedVaults += $Vault.Name
                }
            }
        }
    }

    $returnStatus = 'SUCCESS'
    [string]$returnMessage = ''
    if ($OnlyRemoveEmptyVaults -eq $true) {
        $returnMessage = "* Vaults with registered clients were not removed *`n"
    }

    $returnMessage += "$($VaultCount.ToString().PadLeft(2)) vaults found`n"
    $returnMessage += "$($IgnoredCount.ToString().PadLeft(2)) vaults were skipped`n"
    if ($IgnoredCount -gt 0) {$returnMessage += "   - $($IgnoredVaults -Join ""`n   - "")`n"}
    $returnMessage += "$($RemovedCount.ToString().PadLeft(2)) vaults were successfully removed`n"
    if ($RemovedCount -gt 0) {$returnMessage += "   - $($RemovedVaults -Join ""`n   - "")`n"}
    if ($FailedCount -gt 0) {
        $returnStatus = 'WARNING'
        $returnMessage += "$($FailedCount.ToString().PadLeft(2)) vaults failed to be deleted`n"
        $returnMessage += "   - $($FailedVaults -Join ""`n   - "")`n"
    }

} catch {
    $returnStatus = 'FAILURE'
    $returnMessage = "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
}

# Return output suitable for SNow
Write-Output $returnStatus
Write-Output $returnMessage
Write-Output "`n-- Verbose Log --"
Write-Output $VerboseLog