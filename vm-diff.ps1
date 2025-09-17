# PowerShell script to read JSON file, extract Azure VM names, find their subscription and resource group,
# retrieve each VM's configuration, and save it to a dedicated JSON file.

param (
    [Parameter(Mandatory=$true)]
    [string]$JsonFilePath
)

# Ensure required modules are imported
Import-Module Az.Accounts -ErrorAction SilentlyContinue
Import-Module Az.Compute -ErrorAction SilentlyContinue
Import-Module Az.ResourceGraph -ErrorAction SilentlyContinue

# Read and parse the JSON file
$jsonContent = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json

# Extract the VM names from the nested structure (assuming comma-separated string)
$argsObject = $jsonContent.actions[0].args[0]
$vmNamesString = $argsObject.'-azVMS'
$vmNames = $vmNamesString -split ',' | ForEach-Object { $_.Trim() }

# Save the current Azure context to restore later
$currentContext = Get-AzContext

# Process each VM
foreach ($vmName in $vmNames) {
    Write-Output "Processing VM: $vmName"

    # Use Azure Resource Graph to find the subscription and resource group for the VM
    $query = "Resources | where type =~ 'microsoft.compute/virtualmachines' and name =~ '$vmName' | project subscriptionId, resourceGroup"
    $results = Search-AzGraph -Query $query

    if ($results.Count -eq 0) {
        Write-Warning "No VM found with name '$vmName'. Skipping."
        continue
    } elseif ($results.Count -gt 1) {
        Write-Warning "Multiple VMs found with name '$vmName'. Skipping to avoid ambiguity."
        continue
    }

    $subId = $results.subscriptionId
    $rg = $results.resourceGroup

    # Switch to the correct subscription context
    Set-AzContext -SubscriptionId $subId -ErrorAction Stop

    # Retrieve the VM configuration
    $vmConfig = Get-AzVM -ResourceGroupName $rg -Name $vmName -ErrorAction Stop

    # Save the configuration to a dedicated file
    $outputFile = "$vmName-config.json"
    $vmConfig | ConvertTo-Json -Depth 100 | Out-File -FilePath $outputFile -Encoding utf8
    Write-Output "Configuration saved to $outputFile"
}

# Restore the original context
Set-AzContext -Context $currentContext

Write-Output "Processing complete."