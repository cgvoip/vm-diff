#Requires -Version 7.0
<#
.SYNOPSIS
  Compare two Azure VM inventory exports (from audit-vm.ps1) and report differences.
.DESCRIPTION
  Compares JSON files between baseline and current directories.
  Identifies added, removed, and changed resources for VMs (models, instance views, extensions),
  and other resources (NICs, PIPs, disks, VNets, subnets, NSGs).
  Changes are detected by comparing serialized JSON (exact match).
  Does not provide detailed diffs; use external tools for that.
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$BaselineDir,

  [Parameter(Mandatory = $true)]
  [string]$CurrentDir,

  [Parameter(Mandatory = $false)]
  [string]$ReportFile = "diff-report.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers ---
function Get-Resources {
  param(
    [string]$Dir,
    [string]$SubDir,
    [string]$Filter = '*.json',
    [string]$ExcludePattern # NOTE: optional filename-level exclude (regex)
  )
  $path = Join-Path $Dir $SubDir
  if (-not (Test-Path $path)) { return @{} }
  $files = Get-ChildItem -Path $path -Filter $Filter -File
  $res = @{}
  foreach ($f in $files) {
    if ($ExcludePattern -and ($f.Name -match $ExcludePattern)) { continue } # NOTE
    try {
      $json = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
      if ($json.id) {
        $res[$json.id.ToLowerInvariant()] = $json  # Normalize case for IDs
      }
    } catch {
      Write-Warning "Failed to load $($f.FullName): $_"
    }
  }
  return $res
}

function Get-VmAssociated {
  param(
    [string]$Dir,
    [string]$Suffix  # e.g., '_instanceView.json' or '_extensions.json'
  )
  $path = Join-Path $Dir 'vms'
  if (-not (Test-Path $path)) { return @{} }
  $files = Get-ChildItem -Path $path -Filter "*$Suffix" -File
  $assoc = @{}
  foreach ($f in $files) {
    try {
      # Derive model filename from associated filename
      $modelName = $f.Name -replace [regex]::Escape($Suffix), '.json'
      $modelPath = Join-Path $f.DirectoryName $modelName
      if (Test-Path $modelPath) {
        $modelJson = Get-Content $modelPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        $assocJson = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
        if ($modelJson.id) {
          $assoc[$modelJson.id.ToLowerInvariant()] = $assocJson
        }
      } else {
        Write-Warning "No matching model file for $($f.Name)"
      }
    } catch {
      Write-Warning "Failed to process $($f.FullName): $_"
    }
  }
  return $assoc
}

function Compare-Hashes {
  param(
    [hashtable]$Base,
    [hashtable]$Curr
  )
  $added   = @($Curr.Keys   | Where-Object { -not $Base.ContainsKey($_) } | Sort-Object) # NOTE: sort
  $removed = @($Base.Keys   | Where-Object { -not $Curr.ContainsKey($_) } | Sort-Object)
  $common  = @($Base.Keys   | Where-Object {  $Curr.ContainsKey($_) }   | Sort-Object)
  $changed = @()
  foreach ($k in $common) {
    $baseJson = $Base[$k] | ConvertTo-Json -Depth 100 -Compress
    $currJson = $Curr[$k] | ConvertTo-Json -Depth 100 -Compress
    if ($baseJson -ne $currJson) { $changed += $k }
  }
  return @{
    Added   = $added
    Removed = $removed
    Changed = $changed
  }
}

function Get-ResourceName {
  param([object]$Res)
  if ($Res.name -and $Res.resourceGroup) {
    return "$($Res.resourceGroup)/$($Res.name)"
  } elseif ($Res.id) {
    $parts = ($Res.id -split '/')
    $rg = if ($parts.Length -ge 5) { $parts[4] } else { 'UnknownRG' }
    $name = $parts[-1]
    return "$rg/$name"
  }
  return 'Unknown'
}

# --- Validate dirs ---
if (-not (Test-Path $BaselineDir -PathType Container)) { throw "BaselineDir not found: $BaselineDir" }
if (-not (Test-Path $CurrentDir -PathType Container))  { throw "CurrentDir not found: $CurrentDir" }

# --- Prepare report ---
$reportPath = if ([IO.Path]::IsPathRooted($ReportFile)) { $ReportFile } else { Join-Path (Get-Location) $ReportFile }
$null = New-Item -Path $reportPath -ItemType File -Force
function Write-Report { param([string]$Message) $Message | Out-File -FilePath $reportPath -Append -Encoding UTF8; Write-Host $Message }

Write-Report "Azure VM Inventory Comparison"
Write-Report "Baseline: $BaselineDir"
Write-Report "Current:  $CurrentDir"
Write-Report "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Report ""

# --- Compare VMs (models) ---
Write-Report "## VM Models"
# NOTE: we do NOT need to filter out instanceView/extensions here; those files lack an 'id' and are skipped by Get-Resources
$baseVmModels = Get-Resources -Dir $BaselineDir -SubDir 'vms' -Filter '*.json'
$currVmModels = Get-Resources -Dir $CurrentDir  -SubDir 'vms' -Filter '*.json'
$vmDiff = Compare-Hashes -Base $baseVmModels -Curr $currVmModels

if ($vmDiff.Added.Count -eq 0 -and $vmDiff.Removed.Count -eq 0 -and $vmDiff.Changed.Count -eq 0) {
  Write-Report "No differences."
} else {
  if ($vmDiff.Added.Count -gt 0) {
    Write-Report "### Added VMs:"
    foreach ($id in $vmDiff.Added) { Write-Report "- $(Get-ResourceName $currVmModels[$id]) ($id)" }
  }
  if ($vmDiff.Removed.Count -gt 0) {
    Write-Report "### Removed VMs:"
    foreach ($id in $vmDiff.Removed) { Write-Report "- $(Get-ResourceName $baseVmModels[$id]) ($id)" }
  }
  if ($vmDiff.Changed.Count -gt 0) {
    Write-Report "### Changed VMs:"
    foreach ($id in $vmDiff.Changed) { Write-Report "- $(Get-ResourceName $baseVmModels[$id]) ($id)" }
  }
}
Write-Report ""

# --- Compare VM Instance Views ---
Write-Report "## VM Instance Views"
$baseIvs = Get-VmAssociated -Dir $BaselineDir -Suffix '_instanceView.json'
$currIvs = Get-VmAssociated -Dir $CurrentDir  -Suffix '_instanceView.json'
$ivDiff = Compare-Hashes -Base $baseIvs -Curr $currIvs

if ($ivDiff.Added.Count -eq 0 -and $ivDiff.Removed.Count -eq 0 -and $ivDiff.Changed.Count -eq 0) {
  Write-Report "No differences."
} else {
  if     ($ivDiff.Added.Count   -gt 0) { Write-Report "### Added Instance Views:";   foreach ($id in $ivDiff.Added)   { Write-Report "- VM ID: $id" } }
  if     ($ivDiff.Removed.Count -gt 0) { Write-Report "### Removed Instance Views:"; foreach ($id in $ivDiff.Removed) { Write-Report "- VM ID: $id" } }
  if     ($ivDiff.Changed.Count -gt 0) { Write-Report "### Changed Instance Views:"; foreach ($id in $ivDiff.Changed) { Write-Report "- VM ID: $id" } }
}
Write-Report ""

# --- Compare VM Extensions ---
Write-Report "## VM Extensions"
$baseExts = Get-VmAssociated -Dir $BaselineDir -Suffix '_extensions.json'
$currExts = Get-VmAssociated -Dir $CurrentDir  -Suffix '_extensions.json'
$extDiff = Compare-Hashes -Base $baseExts -Curr $currExts

if ($extDiff.Added.Count -eq 0 -and $extDiff.Removed.Count -eq 0 -and $extDiff.Changed.Count -eq 0) {
  Write-Report "No differences."
} else {
  if     ($extDiff.Added.Count   -gt 0) { Write-Report "### Added Extensions:";   foreach ($id in $extDiff.Added)   { Write-Report "- VM ID: $id" } }
  if     ($extDiff.Removed.Count -gt 0) { Write-Report "### Removed Extensions:"; foreach ($id in $extDiff.Removed) { Write-Report "- VM ID: $id" } }
  if     ($extDiff.Changed.Count -gt 0) { Write-Report "### Changed Extensions:"; foreach ($id in $extDiff.Changed) { Write-Report "- VM ID: $id" } }
}
Write-Report ""

# --- Compare other resources ---
$otherTypes = @(
  @{Name='NICs';       SubDir='nics'    }
  @{Name='Public IPs'; SubDir='pips'    }
  @{Name='Disks';      SubDir='disks'   }
  @{Name='VNets';      SubDir='vnets'   }
  @{Name='Subnets';    SubDir='subnets' }
  @{Name='NSGs';       SubDir='nsgs'    }
)

foreach ($type in $otherTypes) {
  Write-Report "## $($type.Name)"
  $baseRes = Get-Resources -Dir $BaselineDir -SubDir $type.SubDir
  $currRes = Get-Resources -Dir $CurrentDir  -SubDir $type.SubDir
  $diff = Compare-Hashes -Base $baseRes -Curr $currRes

  if ($diff.Added.Count -eq 0 -and $diff.Removed.Count -eq 0 -and $diff.Changed.Count -eq 0) {
    Write-Report "No differences."
  } else {
    if ($diff.Added.Count -gt 0) {
      Write-Report "### Added:";   foreach ($id in $diff.Added)   { Write-Report "- $(Get-ResourceName $currRes[$id]) ($id)" }
    }
    if ($diff.Removed.Count -gt 0) {
      Write-Report "### Removed:"; foreach ($id in $diff.Removed) { Write-Report "- $(Get-ResourceName $baseRes[$id]) ($id)" }
    }
    if ($diff.Changed.Count -gt 0) {
      Write-Report "### Changed:"; foreach ($id in $diff.Changed) { Write-Report "- $(Get-ResourceName $baseRes[$id]) ($id)" }
    }
  }
  Write-Report ""
}

# --- Compare summary vms.json if present ---
$baseSummary = Join-Path $BaselineDir 'vms.json'
$currSummary = Join-Path $CurrentDir  'vms.json'
if (Test-Path $baseSummary -and Test-Path $currSummary) {
  Write-Report "## VM Summary (vms.json)"
  $baseJson = Get-Content $baseSummary -Raw | ConvertFrom-Json -Depth 100 | ConvertTo-Json -Depth 100 -Compress
  $currJson = Get-Content $currSummary -Raw | ConvertFrom-Json -Depth 100 | ConvertTo-Json -Depth 100 -Compress
  if ($baseJson -eq $currJson) { Write-Report "No differences." } else { Write-Report "Differences detected in summary file." }
  Write-Report ""
}

Write-Report "Comparison complete. Report saved to $reportPath"
