# Azure VM Configuration Extraction Script Wiki

## Overview
This PowerShell script automates the process of reading a JSON file containing Azure Virtual Machine (VM) names, retrieving each VM's configuration, and saving it to a dedicated JSON file. The script handles VMs across different Azure subscriptions by dynamically identifying the subscription and resource group for each VM using Azure Resource Graph.

## Purpose
The script is designed to:
- Parse a JSON file to extract Azure VM names.
- Query Azure Resource Graph to determine the subscription and resource group for each VM.
- Retrieve the full configuration of each VM using Azure PowerShell cmdlets.
- Save each VM's configuration to a separate JSON file for documentation or analysis.

## JSON Input Format
The script expects a JSON file with the following structure:
```json
{ "actions": [ {"args": [{"-azVMS": "vm1,vm2,vm3"}]} ] }
```
- The `-azVMS` field contains a comma-separated list of VM names (e.g., `vm1,vm2,vm3`).

## Prerequisites
- **PowerShell**: Version 5.1 or later (PowerShell 7.x recommended).
- **Azure PowerShell Modules**:
  - `Az.Accounts`
  - `Az.Compute`
  - `Az.ResourceGraph`
  - Install using: `Install-Module -Name Az -AllowClobber -Scope CurrentUser`
- **Azure Permissions**: 
  - Access to an Azure account with sufficient permissions to read VM configurations (`Microsoft.Compute/virtualMachines/read`) and query resources via Azure Resource Graph.
- **Authentication**: The user must be logged into Azure via `Connect-AzAccount` before running the script.
- **JSON File**: A valid JSON file containing the VM names in the specified format.

## Script Usage
### Parameters
- **JsonFilePath** (Mandatory): The path to the JSON file containing the VM names.
  - Example: `-JsonFilePath "C:\path\to\input.json"`

### Example Command
```powershell
.\ExtractAzureVMConfig.ps1 -JsonFilePath "C:\path\to\input.json"
```

### Workflow
1. **Read JSON**: The script reads the JSON file and extracts VM names from the `-azVMS` field in the `actions.args` array.
2. **Query Resource Graph**: For each VM, it uses `Search-AzGraph` to find the subscription ID and resource group.
3. **Switch Context**: The script switches to the appropriate Azure subscription using `Set-AzContext`.
4. **Retrieve Configuration**: It fetches the VM configuration using `Get-AzVM`.
5. **Save Output**: The configuration is saved as a JSON file named `<VMName>-config.json`.
6. **Restore Context**: The original Azure context is restored after processing.

### Output
- For each VM, a JSON file (e.g., `vm1-config.json`) is created in the script's working directory.
- The file contains the full configuration of the VM, including hardware, network, and storage details, as returned by `Get-AzVM`.
- Console output provides progress updates and warnings for VMs not found or with ambiguous matches.

## Error Handling
- **Missing VM**: If a VM is not found, a warning is displayed, and the script continues to the next VM.
- **Ambiguous VM Names**: If multiple VMs with the same name exist, the script skips the VM to avoid errors.
- **Authentication Issues**: The script assumes a valid Azure session. If not authenticated, run `Connect-AzAccount` first.
- **Invalid JSON**: If the JSON file is malformed, the script will throw an error during `ConvertFrom-Json`.

## Example Output Files
For a VM named `vm1`, the output file `vm1-config.json` might look like:
```json
{
  "ResourceGroupName": "myResourceGroup",
  "Name": "vm1",
  "Location": "eastus",
  "HardwareProfile": {
    "VmSize": "Standard_D2s_v3"
  },
  ...
}
```

## Limitations
- **Single VM Name Matches**: The script skips VMs with multiple matches to avoid ambiguity. Ensure VM names are unique or refine the Resource Graph query.
- **Depth of JSON Output**: The script uses `-Depth 100` in `ConvertTo-Json` to capture nested properties. Adjust if deeper nesting is required.
- **Azure Context**: The script assumes the user has access to all relevant subscriptions. Missing permissions will cause errors.
- **JSON Structure**: The script expects the exact JSON structure shown. Variations may require code adjustments.

## Troubleshooting
- **Error: "No VM found"**: Verify the VM name exists in Azure and is accessible under the user's subscriptions.
- **Error: "Multiple VMs found"**: Ensure VM names are unique or modify the Resource Graph query to include additional filters (e.g., location).
- **Error: "Cannot find module"**: Install the required Az modules using `Install-Module`.
- **Slow Performance**: Large numbers of VMs or slow Azure API responses may increase runtime. Consider batching or optimizing the Resource Graph query.

## Security Considerations
- **Permissions**: Use the principle of least privilege for the Azure account. Avoid granting unnecessary access.
- **Output Files**: The generated JSON files contain sensitive VM configuration details (e.g., network interfaces). Store them securely and avoid sharing publicly.
- **Authentication**: Ensure `Connect-AzAccount` uses a secure method (e.g., interactive login or service principal).

## Future Enhancements
- Add support for custom output paths for JSON files.
- Include additional VM properties (e.g., disk configurations, tags) via custom queries.
- Handle multiple VMs with the same name by filtering on additional criteria (e.g., location, resource group).
- Add parallel processing for faster execution with many VMs.

## Source Code
The script is available below for reference:

<xaiArtifact artifact_id="0baa6027-cf2d-4b0c-8e77-4d5f197c8b4c" artifact_version_id="396a179a-627f-4c6a-a590-e0bffb8201e4" title="ExtractAzureVMConfig.ps1" contentType="text/powershell">
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