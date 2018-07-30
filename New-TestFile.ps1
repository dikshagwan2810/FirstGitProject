<#
    .SYNOPSIS
        Generates a simple test case JSON file for a supplied script

    .DESCRIPTION
        Generates a JSON file to be used as a starting point for creating test cases.  The input script MUST have valid comment-based help.  The comment-based help MUST start on the first line of the script. Any #Requires or [cmdletBinding()] directives should come AFTER the help comments.

    .EXAMPLE
        New-TestFile.ps1 -ScriptPath .\New-VM.ps1

    .NOTES
        Author:     Russell Pitcher
        Company:    Atos
        Email:      russell.pitcher@atos.net
        Created:    2017-10-05
        Updated:    2017-10-05
        Version:    0.1
#>

[cmdletBinding()]
Param (
    # The path to the script to generate a test file for
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

function New-TestElement {
    Param (
        $RunbookName,
        $scriptParameters,
        $Description,
        $CheckMethod,
        $testId,
        $ChangedParameter,
        $ChangedParameterValue,
        $ExpectedOutput

    )

    $elementHeader = @"
        {
          "Type": "InvokeRunbook",
          "Elements": {
            "RunbookParameters": {
              "properties": {
                "runbook": {
                  "name": "${RunbookName}",
                  "Description": "$($Description)"
                },
                "parameters": {
"@

    $ParameterBody = ''
    $ParameterArray = @()
    forEach ($Parameter in $scriptParameters) {
        if ($Parameter.Name -eq $ChangedParameter) {
            if ($ChangedParameterValue -ne '[remove]') {
                $ParameterArray += "`"$($Parameter.Name)`": `"$($ChangedParameterValue)`""
            }
        } else {
            if ($Parameter.Name -match 'RequestorUserAccount|ConfigurationItemId') {
                $ParameterArray += "`"$($Parameter.Name)`": `"TestCase 01.$($TestId.ToString().PadLeft(2,'0'))`""
            } else {
                $ParameterArray += "`"$($Parameter.Name)`": `"$($Parameter.TestValue)`""
            }
        }
    }
    $ParameterBody = $($ParameterArray -join ",`n                  ")

    $ElementFooter = @"

                }
              },
              "CheckMethod": "$($CheckMethod)",
              "RunbookExpectedOutput": "$($ExpectedOutput)"
            }
          }
        }
"@

    "${elementHeader}`n                  ${ParameterBody}${elementFooter}"
    $script:TestId++
}

[int]$script:TestId = 1
$ScriptCommandInfo = Get-Command $ScriptPath
$ScriptHelpInfo = Get-Help $ScriptPath
if (-not $ScriptHelpInfo.Parameters) {
    Write-Host "`nCannot find help parameters for this script!  Please ensure that comment-based help is correctly formatted. You can test this by running this command:" -ForegroundColor Yellow
    Write-Host "`n  .$($ScriptPath.SubString($ScriptPath.LastIndexOf('\'))) -?`n"
    Write-Host "If it returns a single line of help text then comment-based help is not working.  If it returns multiple lines with headings then comment-based help is working.`n" -ForegroundColor Yellow
    exit
}
$RunbookName = $ScriptHelpInfo.Name.split('\')[-1].Replace('.ps1', '')
$ScriptParameters = $ScriptHelpInfo.Parameters.Parameter.Clone()
$jsonHeader = @'
{
  "RunbookTestWorkflow": [
    {
      "Type": "InvokeParallel",
      "Elements": [

'@
$jsonTests = @()
$jsonFooter = @'

      ]
    }
  ]
}
'@

# Add validation patterns for each parameter
Write-Host "`nFound the following script parameters:" -ForegroundColor Yellow
forEach ($Parameter in $ScriptParameters) {
    Write-Host "  $($Parameter.Name) : " -ForegroundColor Green -NoNewline
    $validation = $null
    $Validation = $ScriptCommandInfo.Parameters.$($Parameter.Name).Attributes[0] | Where-Object {$_.TypeId -match 'Validate'}
    if ($null -ne $validation) {
        Switch ($validation.TypeId.ToString().Replace('System.Management.Automation.', '')) {
            "ValidatePatternAttribute" {
                Write-Host "ValidatePattern"
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "RegEx" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value $Validation.RegExPattern -Force
            }
            "ValidateNotNullOrEmptyAttribute" {
                Write-Host "ValidateNotNullOrEmpty"
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "NotNullOrEmpty" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "" -Force
            }
            "ValidateNotNullAttribute" {
                Write-Host "ValidateNotNull"
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "NotNull" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "" -Force
            }
            "ValidateLengthAttribute" {
                Write-Host "ValidateLength"
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "Length" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "$($Validation.MinLength)|$ -Force($Validation.MaxLength)"
            }
            "ValidateRangeAttribute" {
                Write-Host "ValidateRange"
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "Range" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "$($Validation.MinRange)|$ -Force($Validation.MaxRange)"
            }
            default {
                Write-Host "Unhandled validation pattern: $($validation.TypeId.ToString().Replace('System.Management.Automation.', ''))" -ForegroundColor DarkGray
                # Not yet implemented, if at all
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "None" -Force
                $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "" -Force
            }
        }
    } else {
        Write-Host "No Validation" -ForegroundColor Cyan
        # Not yet implemented, if at all
        $Parameter | Add-Member -MemberType NoteProperty -Name ValidationType -Value "None" -Force
        $Parameter | Add-Member -MemberType NoteProperty -Name ValidationPattern -Value "" -Force
    }
}

# Get valid test values from the user for all script parameters
Write-Host "`nEnter valid test values for the following parameters:" -ForegroundColor Yellow
forEach ($Parameter in $ScriptParameters) {
    $TestValue = Read-Host "  $($Parameter.name) "
    $Parameter | Add-Member -MemberType NoteProperty -Name TestValue -Value $TestValue -Force
}

# Generate test strings for each parameter
Write-Host "`nAdding standard failure tests:" -ForegroundColor Yellow
forEach ($Parameter in $ScriptParameters) {
    Write-Host "  Reviewing parameter: $($Parameter.Name)" -fore Green
    if ($Parameter.required -eq 'true') {
        Write-Host "    Adding Test: Missing parameter"
        $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' missing" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue '[remove]' -ExpectedOutput "Cannot process command because of one or more missing mandatory parameters: $($Parameter.Name)."
    } else {
        Write-Host "    Skipping missing test (Required=$($Parameter.required))" -ForegroundColor DarkGray
    }

    switch ($Parameter.ValidationType) {
        'RegEx' {
            Write-Host "    Adding Tests: RegEx"
            # This is the tricky one.  Can't generate a string that *won't* match a given regex.  Try a few likely candidates
            $ChangedValue = ''
            $TestCandidates = @('dfadd3bc-Bad-GUID-766e5f7a5817', '--InvalidValue--', 'x', '1-a-1-a-1')
            forEach ($TestValue in $TestCandidates) {
                if ($TestValue -notmatch $Parameter.ValidationPattern) {
                    $ChangedValue = $TestValue
                    break
                }
            }
            $OutputValue = "Cannot validate argument on parameter '$($Parameter.Name)'. The argument \""$($ChangedValue)\"" does not match the \""$($Parameter.ValidationPattern)\"" pattern. Supply an argument that matches \""$($Parameter.ValidationPattern)\"" and try the command again. (The argument \""$($ChangedValue)\"" does not match the \""$($Parameter.ValidationPattern)\"" pattern. Supply an argument that matches \""$($Parameter.ValidationPattern)\"" and try the command again.)"
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' null" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $ChangedValue -ExpectedOutput $OutputValue
        }
        'NotNull' {
            Write-Host "    Adding Tests: Null"
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' null/empty" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $null -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again. (The argument is null or empty. Provide an argument that is not null or empty, and then try the command again.)"
        }
        'NotNullOrEmpty' {
            Write-Host "    Adding Tests: NullOrEmpty"
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' null/empty" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue '' -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again. (The argument is null or empty. Provide an argument that is not null or empty, and then try the command again.)"
            # Empty parameter value already added
        }
        'Length' {
            Write-Host "    Adding Tests: Length"
            $Min = $Parameter.ValidationPattern.Split('|')[0]
            $Max = $Parameter.ValidationPattern.Split('|')[1]
            if ($Min -gt 0) {
                $TooSmall = $Parameter.TestValue.SubString(0, $Min - 1)
                $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' length too short" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $TooSmall -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The character length ($($TooSmall.Length)) of the argument is too short. Specify an argument with a length that is greater than or equal to "$($Min)", and then try the command again."
            }
            $TooLarge = $Parameter.TestValue.PadRight($Max + 1, "#")
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' length too long" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $TooLarge -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The character length of the $($TooLarge.Length) argument is too long. Shorten the character length of the argument so it is fewer than or equal to "$($Max)" characters, and then try the command again."
        }
        'Range' {
            Write-Host "    Adding Tests: Range"
            $Min = $Parameter.ValidationPattern.Split('|')[0]
            $Max = $Parameter.ValidationPattern.Split('|')[1]
            $TooSmall = $Min - 1
            $TooLarge = $Max + 1
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' value too small" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $TooSmall -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The $($TooSmall) argument is less than the minimum allowed range of $($Min). Supply an argument that is greater than or equal to $($Min) and then try the command again."
            $TooLarge = $Parameter.TestValue.PadRight($Max + 1, "#")
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Parameter '$($Parameter.Name)' value too large" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $TooLarge -ExpectedOutput "Cannot validate argument on parameter '$($Parameter.Name)'. The $($TooLarge) argument is greater than the maximum allowed range of $($Max). Supply an argument that is less than or equal to $($Max) and then try the command again."
        }
        "None" {
            Write-Host "    No Tests"
            # No validation pattern found
        }
        default {
            Write-Host "    Unknown validation" -ForegroundColor Red
            # Dunno
        }
    }

    # Add test cases for likely scenarios if appropriate
    switch ($Parameter.Name) {
        "VirtualMachineName" {
            Write-Host "    Adding Test: Cannot find VM in resource group"
            $FakeVmName = 'missingdavm9999' # This should pass a VM name RegEx test
            $ResourceGroup = ($ScriptParameters | Where-Object {$_.name -eq 'VirtualMachineResourceGroupName'}).TestValue
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Cannot find VM" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $FakeVmName -ExpectedOutput "Cannot find VM ${FakeVmName} in resource group ${ResourceGroup}"
        }
        "VirtualMachineResourceGroupName" {
            Write-Host "    Adding Test: Cannot find resource group"
            $FakeResourceGroup = 'aaa-bbbb-d-rsg-fakegroup' # This should pass a Resource Group RegEx test
            $jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Cannot find Resource Group" -CheckMethod 'String' -TestId $TestId -ChangedParameter $Parameter.Name -ChangedParameterValue $FakeResourceGroup -ExpectedOutput "Resource group '$($FakeResourceGroup)' could not be found"
        }
    }
}


# Add a last test using the entered values that should run successfully
Write-Host "  Adding final SUCCESS test using all supplied values" -ForegroundColor Green
$jsonTests += New-TestElement -RunbookName $RunbookName -scriptParameters $ScriptParameters -Description "Successful test" -CheckMethod 'String' -TestId $TestId -ExpectedOutput "SUCCESS >> EnterSuccessText <<"

# Join it all up and write to file
Write-Host "`nCollating tests and writing file" -ForegroundColor Yellow
$TestBody = $jsonTests -join ",`n"
$($jsonHeader + $TestBody + $jsonFooter) | Out-File -FilePath "Test-$($RunbookName).json" -Encoding ascii

Write-Host "`n`nThe new test file can be found at:" -ForegroundColor Green
Write-Host "`n`n  $((pwd).Path)\Test-$($RunbookName).json`n`n"
Write-Host "Please review it carefully, add the correct text for the SUCCESS output on the last test and add any other tests required using the last test element as a template.`n" -ForegroundColor Green

