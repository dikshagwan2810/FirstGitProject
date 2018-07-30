#Requires -Module AzureRM.Profile
#Requires -Module AzureRM.Automation

<#
.SYNOPSIS
    This runbook imports the a specified version or the latest version of all modules in an Automation account.
    Modules will be imported either from the PowerShell Gallery or a local source.  If a specific version of a
    module, or a new module is required then it must be specified in the JSON input for parameter -ModuleVersions

.DESCRIPTION
    This runbook imports the a specified version or the latest version of all modules in an Automation account.
    Modules will be imported either from the PowerShell Gallery or a local source.  If a specific version of a
    module, or a new module is required then it must be specified in the JSON input for parameter -ModuleVersions

.PARAMETER ResourceGroupName
    Optional. The name of the Azure Resource Group containing the Automation account to update all modules for.
    If a resource group is not specified, then it will use the current one for the automation account
    if it is run from the automation service

.PARAMETER AutomationAccountName
    Optional. The name of the Automation account to update all modules for.
    If an automation account is not specified, then it will use the current one for the automation account
    if it is run from the automation service

.PARAMETER ModuleVersions
    A JSON list of modules and their required version, or 'latest' if you want to update them to the latest version

.EXAMPLE
    Update-ModulesVersions -ResourceGroupName 'MyResourceGroup -AutomationAccountName 'MyAutomationAccount' -ModuleVersions '{"AzureRM.Batch":"3.2.1","AzureRM.RecoveryServices":"latest","Atos.RunbookAutomation":"latest"}'

.NOTES
    AUTHOR: Russell Pitcher, based on a script from the Azure Automation Team
    LASTEDIT: 2017/09/18
#>

param(
    [Parameter(Mandatory = $false)]
    [String] $ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $false)]
    [String] $ModuleVersions
)

function _doImport {
    param(
        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String] $ModuleName,

        # if not specified latest version will be imported
        [Parameter(Mandatory = $false)]
        [String] $ModuleVersion
    )

    $SearchResult = Search-GalleryModule -ModuleName $ModuleName -ModuleVersion $ModuleVersion

    if (!$SearchResult) {
        Write-Warning "  Could not find module '${ModuleName}' on PowerShell Gallery. This may be a module you imported from a different location"
    } else {
        $ModuleName = $SearchResult.title.$('#text') # get correct casing for the module name
        $PackageDetails = Invoke-RestMethod -Method Get -UseBasicParsing -Uri $SearchResult.id

        $ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/${ModuleName}/${ModuleVersion}"
        Write-Verbose "  Module URL: ${ModuleContentUrl}"

        # Find the actual blob storage location of the module
        do {
            $ActualUrl = $ModuleContentUrl
            Write-Verbose "  Checking URL: ${ModuleContentUrl}"
            $ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location
        } while (!$ModuleContentUrl.Contains(".nupkg"))

        $ActualUrl = $ModuleContentUrl

        Write-Verbose "  Importing ${ModuleName} module of version ${ModuleVersion} to Automation using ContentLink ${ActualUrl}"

        try {
            $AutomationModule = New-AzureRmAutomationModule `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $ModuleName `
                -ContentLink $ActualUrl

            while (
                (!([string]::IsNullOrEmpty($AutomationModule))) -and
                $AutomationModule.ProvisioningState -ne "Created" -and
                $AutomationModule.ProvisioningState -ne "Succeeded" -and
                $AutomationModule.ProvisioningState -ne "Failed"
            ) {
                Write-Verbose -Message "  - Polling for module import completion"
                Start-Sleep -Seconds 10
                $AutomationModule = $AutomationModule | Get-AzureRmAutomationModule
            }

            if ($AutomationModule.ProvisioningState -eq "Failed") {
                Write-Error "  Importing ${ModuleName} module to Automation failed."
                $script:ProblemModules += "${ModuleName} : Failed to import version ${ModuleVersion} of module to Automation."
            } else {
                Write-Verbose "  Importing ${ModuleName} module to Automation succeeded."
                $script:ModulesImported += "${ModuleName} [${ModuleVersion}] imported successfully."
            }
        } catch {
            Write-Output "  ERROR: Error while importing module: $($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
            $script:ProblemModules += "${ModuleName} : Importing version ${ModuleVersion} of module to Automation failed: $($_.ToString())"
        }
    }
}

function Search-GalleryModule {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [Alias('Module')]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [Alias('Version')]
        [string]$ModuleVersion = 'latest'
    )

    if ($ModuleVersion -eq 'latest') {
        $Url = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$ModuleName' and IsLatestVersion"
    } else {
        $Url = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$ModuleName' and Version eq '$ModuleVersion'"
    }
    Invoke-RestMethod -Method Get -Uri $Url -UseBasicParsing
}

function Search-ArrayList {
    Param(
        [object]$ArrayList,
        [string]$SearchTerm,
        [string]$Delimiter,
        [switch]$ExactMatch
    )

    $count = 0
    forEach ($Item in $ArrayList) {
        if ($ExactMatch) {
            if ($Delimiter) {
                if ($SearchTerm -ceq $Item.Split($Delimiter)[0]) {
                    return $count
                    break
                } else {
                    $count++
                }
            } else {
                if ($SearchTerm -ceq $Item) {
                    return $count
                    break
                } else {
                    $count++
                }
            }
        } else {
            if ($Delimiter) {
                if ($SearchTerm.ToLower() -like "$($Item.Split($Delimiter)[0].ToLower())") {
                    return $count
                    break
                } else {
                    $count++
                }
            } else {
                if ($Item.ToLower() -like "$($SearchTerm.ToLower())*") {
                    return $count
                    break
                } else {
                    $count++
                }
            }
        }
    }
    return -1
}

function Add-ModuleToInstallList {
    Param(
        [string]$Name,
        [string]$Version,
        [string[]]$BeforeItems,
        [string[]]$AfterItems
    )

    $ModulePosition = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm "${Name}|${Version}"
    if ($ModulePosition -ge 0) {
        Write-Verbose "  Module ${Name} [${Version}] is already in the installation list"
    } else {
        $BeforePosition = 999 # set ridiculously high position to insert item at
        if ($BeforeItems) {
            forEach ($item in $BeforeItems) {
                $thisPosition = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm "${item}" -ExactMatch
                if ($thisPosition -ge 0) {
                    if ($thisPosition -lt $BeforePosition) {$BeforePosition = $thisPosition}
                }
            }
        }

        $AfterPosition = -1
        if ($AfterItems) {
            forEach ($item in $AfterItems) {
                $thisPosition = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm "${item}" -ExactMatch
                if ($thisPosition -ge 0) {
                    if ($thisPosition -gt $AfterPosition) {$AfterPosition = $thisPosition}
                }
            }
        }

        Write-Verbose "!! Need to insert $Name [$Version] after $AfterPosition but before $BeforePosition"
        if ($AfterPosition -gt $BeforePosition) {
            Write-Verbose "!*!*! OOPS !*!*!"
        } else {
            if ($AfterPosition -lt 0) {
                $insertPosition = $BeforePosition
            } else {
                $insertPosition = $AfterPosition + 1
            }
        }

        Write-Verbose "-- insertPosition = $insertPosition"
        # Insert if position is within array, or add to end
        if ($insertPosition -lt $OrderedModulesAndVersions.Count) {
            if ($insertPosition -eq -1) {$insertPosition = 0} # Just in case...
            $ModulePosition = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm "${Name}"
            if ($ModulePosition -ge 0) {
                $InstallListVersion = $OrderedModulesAndVersions[$ModulePosition].Split('|')[1]
                if ($Version -lt [Version]$InstallListVersion) {
                    if ($ModulePos -le $insertPosition) {
                        $pos = $OrderedModulesAndVersions.Insert($ModulePosition, "${Name}|${Version}")
                    } else {
                        $pos = $OrderedModulesAndVersions.Insert($insertPosition, "${Name}|${Version}")
                    }
                } else {
                    $pos = $OrderedModulesAndVersions.Insert($insertPosition, "${Name}|${Version}")
                }
            } else {
                $pos = $OrderedModulesAndVersions.Insert($insertPosition, "${Name}|${Version}")
            }
        } else {
            $ModulePosition = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm "${Name}"
            if ($ModulePosition -ge 0) {
                $InstallListVersion = $OrderedModulesAndVersions[$ModulePosition].Split('|')[1]
                if ($Version -lt [Version]$InstallListVersion) {
                    $pos = $OrderedModulesAndVersions.Insert($ModulePosition, "${Name}|${Version}")
                } else {
                    $pos = $OrderedModulesAndVersions.Add("${Name}|${Version}")
                }
            } else {
                $pos = $OrderedModulesAndVersions.Add("${Name}|${Version}")
            }
        }
    }
}

#$ErrorActionPreference = 'stop'
$NonGalleryModules = @{}
$ModulesAndVersions = @{}
$ModuleCurrentVersions = @{}
$ModuleDependencies = @{}
$script:OrderedModulesAndVersions = [System.Collections.ArrayList]@()
$script:ModulesImported = [System.Collections.ArrayList]@()
$script:ProblemModules = [System.Collections.ArrayList]@()
$KnownExceptions = "Microsoft.PowerShell.Core", `
    "Microsoft.PowerShell.Utility", `
    "Microsoft.PowerShell.Security", `
    "Microsoft.PowerShell.Management", `
    "Microsoft.PowerShell.Diagnostics", `
    "Microsoft.WSMan.Management", `
    "Orchestrator.AssetManagement.Cmdlets"

# Get connected
try {
    $RunAsConnection = Get-AutomationConnection -Name "DefaultRunAsConnection"

    Write-Output "Logging in to Azure..."
    $AddAccount = Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $RunAsConnection.TenantId `
        -ApplicationId $RunAsConnection.ApplicationId `
        -CertificateThumbprint $RunAsConnection.CertificateThumbprint

    Select-AzureRmSubscription -SubscriptionId $RunAsConnection.SubscriptionID  | Write-Verbose

    # Find the automation account or resource group is not specified
    if (([string]::IsNullOrEmpty($ResourceGroupName)) -or ([string]::IsNullOrEmpty($AutomationAccountName))) {
        Write-Output ("Finding the ResourceGroup and AutomationAccount that this job is running in ...")
        if ([string]::IsNullOrEmpty($PSPrivateMetadata.JobId.Guid)) {
            throw "This is not running from the automation service. Please specify ResourceGroupName and AutomationAccountName as parameters"
        }
        $AutomationResource = Find-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts

        foreach ($Automation in $AutomationResource) {
            $Job = Get-AzureRmAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
            if (!([string]::IsNullOrEmpty($Job))) {
                $ResourceGroupName = $Job.ResourceGroupName
                $AutomationAccountName = $Job.AutomationAccountName
                Write-Verbose "Discovered resource group name: ${ResourceGroupName}"
                Write-Verbose "Discovered automation account name: ${AutomationAccountName}"
                break;
            }
        }
    }

    # Check automation account and resource group once again
    if (([string]::IsNullOrEmpty($ResourceGroupName)) -or ([string]::IsNullOrEmpty($AutomationAccountName))) {
        throw "Failed to discover ResourceGroupName '$ResourceGroupName' or AutomationAccountName '$AutomationAccountName'"
    }
} catch {
    if (!$RunAsConnection) {
        throw "Connection AzureRunAsConnection not found. Please create one"
    } else {
        throw $_.Exception
    }
}

try {
    Write-Output "Parsing Required modules"
    (ConvertFrom-Json $ModuleVersions).PsObject.properties | ForEach-Object {$ModulesAndVersions.Add($_.Name, $_.Value)}


    # Adding any installed modules that are not in the list.  Assuming they should be updated to the latest version.
    Write-Output "Getting details of currently installed modules"
    $Modules = Get-AzureRmAutomationModule `
        -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName
    foreach ($Module in $Modules) {
        # $Module = Get-AzureRmAutomationModule `
        #     -ResourceGroupName $ResourceGroupName `
        #     -AutomationAccountName $AutomationAccountName `
        #     -Name $Module.Name
        Write-Verbose "Found module '$($Module.Name)' at version $($Module.Version)"
        $ModuleCurrentVersions.Add($Module.Name, $Module.Version)

        if (($null -eq $ModulesAndVersions.$($Module.Name)) -and ($Module.Name -notin $KnownExceptions)) {
            Write-Output "WARNING: Module '$($Module.Name)' does not appear in the list of required modules, please add it to the list.  It will be updated to the latest version if necessary"
            $script:ProblemModules += "$($Module.Name) : Please add to list of version controlled modules"
            $ModulesAndVersions.Add($Module.Name, 'latest')
        }
    }

    Write-Verbose "-------------- Working through supplied list ---------------"

    Write-Output "Finding modules in PowerShell Gallery and checking versions and dependencies"
    forEach ($ModuleName in $ModulesAndVersions.Keys) {
        Write-Verbose "Checking module '${Modulename}'"
        Write-Verbose "-- current list --"
        Write-Verbose ($OrderedModulesAndVersions | Format-Table | Out-String)
        Write-Verbose "------------------"
        if (!([string]::IsNullOrEmpty($ModuleName))) {
            $skip = $false
            Write-Verbose "  Checking if module '${ModuleName}' is at the required version in your automation account"
            if ($ModulesAndVersions.$ModuleName -eq 'latest') {
                $Module = Search-GalleryModule -ModuleName $ModuleName
                if ($null -eq $Module) {
                    Write-Verbose "  Could not find module '${ModuleName}' on PowerShell Gallery. This may be a module you imported from a different location"
                    # Add it to the list of modules to attempt to install from local source
                    $NonGalleryModules.Add($ModuleName, $ModulesAndVersions.$ModuleName)
                    $skip = $true
                } else {
                    $RequiredVersion = $Module.Properties.Version
                }
            } else {
                $RequiredVersion = $ModulesAndVersions.$ModuleName
                $Module = Search-GalleryModule -ModuleName $ModuleName -ModuleVersion $RequiredVersion
            }

            if (!$skip) {
                $ModuleDependencies.Add($ModuleName, $Module.Properties.Dependencies)
                if ($ModuleCurrentVersions.$ModuleName -eq $RequiredVersion) {
                    Write-Output "  Module '${ModuleName}' is already at the required version (${RequiredVersion})."
                } else {
                    Write-Output "  Module '${ModuleName}' needs to be updated from version $($ModuleCurrentVersions.$ModuleName) to version ${RequiredVersion}"
                    Write-Verbose "  Dependencies: $($Module.Properties.Dependencies)"
                    if ([string]::IsNullOrEmpty($Module.Properties.Dependencies)) {
                        Write-Verbose "  No depencencies"
                        Add-ModuleToInstallList -OrderedList $OrderedModulesAndVersions -Name $ModuleName -Version $RequiredVersion
                    } else {
                        $Dependencies = $Module.Properties.Dependencies.Split('|') | ForEach-Object {$_.Replace(':[', '|').Replace(']:', '')}
                        Add-ModuleToInstallList -OrderedList $OrderedModulesAndVersions -Name $ModuleName -Version $RequiredVersion -AfterItems $Dependencies
                        $BeforeItems = , "${ModuleName}|${RequiredVersion}"
                        ForEach ($Dependency in $Dependencies) {
                            Write-Verbose "    Dependency: '${Dependency}'"
                            try {
                                $DependingModule = $Dependency.Split('|')
                                Write-Verbose "    - Adding $($DependingModule[0]), $($DependingModule[1])"
                                Add-ModuleToInstallList -OrderedList $OrderedModulesAndVersions -Name $DependingModule[0] -Version $DependingModule[1] -BeforeItems $BeforeItems
                            } catch {
                                Write-Verbose "    ERROR: Failed to add dependency '${Dependency}'"
                            }
                        }
                    }
                }
            }
        }
    }

    Write-Output "Cleaning list of modules known not to be available from the gallery or local repository"
    forEach ($Exception in $KnownExceptions) {
        Write-Verbose "Removing known exception '${Exception}' from install list"
        $NonGalleryModules.Remove($Exception)
        $item = Search-ArrayList -ArrayList $OrderedModulesAndVersions -SearchTerm $Exception -Delimiter '|'
        if ($item -ge 0) {
            $OrderedModulesAndVersions.Remove($OrderedModulesAndVersions[$item])
        }
    }

    Write-Verbose "`n----------Current Modules----------------"
    Write-Verbose ($ModuleCurrentVersions | Format-Table -AutoSize | Out-String)

    Write-Verbose "`n----------Dependency List----------------"
    Write-Verbose ($ModuleDependencies | Format-Table -AutoSize | Out-String)

    Write-Verbose "`n----------Gallery modules for installation----------------"
    Write-Verbose ($OrderedModulesAndVersions | Format-Table -AutoSize | Out-String)

    Write-Verbose "`n----------Local modules for installation----------------"
    Write-Verbose ($NonGalleryModules | Format-Table -AutoSize | Out-String)
} catch {
    Write-Output "-------------------------"
    Write-Output "FAILED to set module installation order"
    Write-Output "$($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
    Write-Output "-------------------------"
    $_
    exit
}

Write-Output "`nImporting gallery modules"
forEach ($Module in $OrderedModulesAndVersions) {
    $thisModule = $Module.Split('|')
    Write-Output "Importing module $($thisModule[0]) [$($thisModule[1])] into your automation account"
    _doImport -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ModuleName $thisModule[0] -ModuleVersion $thisModule[1]
}

Write-Output "`nImporting locally sourced modules"

Write-Output "Get StorageAccount"
$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName
$StorageAccountName = $StorageAccount.StorageAccountName
if ($StorageAccount -eq $null -or $StorageAccount -eq "") {
    throw "No Storage Account found in Resource Group '${ResourceGroupName}'"
} elseif ($StorageAccount.count -gt 1) {
    throw "Resource Group '${ResourceGroupName}'' contains $($StorageAccount.count) storage accounts where 1 was expected"
}
Write-Output "Found storage account '${StorageAccountName}'"
$StorageAccountKey = Get-AzureRmStorageAccountKey -Name $StorageAccountName -ResourceGroupName $ResourceGroupName
if ([string]::IsNullOrEmpty($StorageAccountKey)) {
    throw "Did not retrieve a valid storage account key"
}

# $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey[0].Value -ErrorAction SilentlyContinue

Write-Output "Importing local modules"
forEach ($ModuleName in $NonGalleryModules.Keys) {
    $Url = "https://${StorageAccountName}.blob.core.windows.net/modules/${ModuleName}.zip"
    Write-Output "Importing module ${ModuleName} from ${Url}"
    try {
        $ResourceCheck = Invoke-WebRequest -Uri $Url -DisableKeepAlive -UseBasicParsing -Method Head -ErrorAction SilentlyContinue
    } catch {
        $ResourceCheck = $null
    }

    if ($null -eq $ResourceCheck) {
        Write-Output "  ERROR: Cannot find source file for module ${ModuleName}"
        $script:ProblemModules += "${ModuleName} : Cannot find module on PowerShellGallery or local repository"
    } else {
        try {
            $AutomationModule = New-AzureRmAutomationModule `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $ModuleName `
                -ContentLink $Url

            while (
                (!([string]::IsNullOrEmpty($AutomationModule))) -and
                $AutomationModule.ProvisioningState -ne "Created" -and
                $AutomationModule.ProvisioningState -ne "Succeeded" -and
                $AutomationModule.ProvisioningState -ne "Failed"
            ) {
                Write-Verbose "  - Polling for module import completion"
                Start-Sleep -Seconds 10
                $AutomationModule = $AutomationModule | Get-AzureRmAutomationModule
            }

            if ($AutomationModule.ProvisioningState -eq "Failed") {
                Write-Output "  FAILED to import ${ModuleName} to Automation Account."
                $script:ProblemModules += "${ModuleName} : Failed to import module from local source"
            } else {
                $script:ModulesImported += "${ModuleName} [${ModuleVersion}] imported successfully."
            }
        } catch {
            Write-Output "  ERROR importing module: $($_.ToString()) [$($_.InvocationInfo.ScriptLineNumber),$($_.InvocationInfo.OffsetInLine)]"
            $script:ProblemModules += "${ModuleName} : Failed to import module from local source"
        }
    }
}

if ($script:ModulesImported.length -gt 0) {
    Write-Output "`nThe following modules were imported"
    $script:ModulesImported | ForEach-Object {
        Write-Output " - $_"
    }
}

if ($script:ProblemModules.length -gt 0) {
    Write-Output "`nThe following modules may need your attention:"
    $script:ProblemModules | ForEach-Object {
        Write-Output " - $_"
    }
}

Write-Output "`nFinished"
