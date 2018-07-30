#Requires -Version 5.0
#Requires -RunAsAdministrator

<#  
.SYNOPSIS  
    Exports the Run As certificate from an Azure Automation account to a hybrid worker in that account.

.DESCRIPTION  
    This runbook exports the Run As certificate from an Azure Automation account to a hybrid worker in that account.
    Run this runbook in the hybrid worker where you want the certificate installed.
    This allows the use of the AzureRunAsConnection to authenticate to Azure and manage Azure resources from runbooks running in the hybrid worker.

.INPUTS
    $Password: Enter unique password for the certificate
    $RunAsCert: Enter certificate name from Certificates Assests
    $CertPath: Enter certificate name from Certificates Assests with .pfx extension
    $RunAsConnection: Enter certificate name from Certificates Assests

.OUTPUTS
    Certificates would be deployed and imported into hybrid runbook worker (Certificates (Local Computer) > Personal > Certificates) depending on the number of certificates within Certificates Assests

.EXAMPLE
    .\Export-RunAsCertificateToHybridWorker

.NOTES
    AUTHOR: Austin Palakunnel, Brijesh Shah
    COMPANY: Atos
    Email: austin.palakunnel@atos.net, brijesh.shah@atos.net
    Created: 2016.10.13
    VERSION: 1.0
#>

try
{
[OutputType([string])]

# Set the password used for this certificate
$Password = -join (33..126 | ForEach-Object {[char]$_} | Get-Random -Count 16)

# Stop on errors
$ErrorActionPreference = 'stop'

# Get the management certificate that will be used to make calls into Azure Service Management resources
$RunAsCert = Get-AutomationCertificate -Name "AzureRunAsCertificate"

# location to store temporary certificate in the Automation service host
$CertPath = Join-Path $env:temp  "AzureRunAsCertificate.pfx"

# Save the certificate
$Cert = $RunAsCert.Export("pfx",$Password)
Set-Content -Value $Cert -Path $CertPath -Force -Encoding Byte | Write-Verbose

Write-Output -InputObject ("Importing certificate into $env:computername local machine root store from " + $CertPath)
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
Import-PfxCertificate -FilePath $CertPath -CertStoreLocation Cert:\LocalMachine\My -Password $SecurePassword -Exportable | Write-Verbose

# Get the azure automation connection with the properties
$RunAsConnection = Get-AutomationConnection -Name "AzureRunAsConnection"

 $AzureRmAccountParameters = @{
    ServicePrincipal = $true
    TenantId = $RunAsConnection.TenantId
    ApplicationId = $RunAsConnection.ApplicationId
    CertificateThumbprint = $RunAsConnection.CertificateThumbprint
}
Add-AzureRmAccount @AzureRmAccountParameters | Write-Verbose

Set-AzureRmContext -SubscriptionId $RunAsConnection.SubscriptionID | Write-Verbose

Remove-Item -Path C:\Windows\Temp\*.pfx
}

catch
{
    throw "$_"
}