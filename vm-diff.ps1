# PowerShell script to compare Azure VM configuration JSON files with matching prefixes
# in two different folders, verify prefix count, report missing files, and output differences.

param (
    [Parameter(Mandatory=$true)]
    [string]$PreFolder,

    [Parameter(Mandatory=$true)]
    [string]$PostFolder
)

# Function for recursive comparison of two PSCustomObjects
function Compare-Objects {
    param (
        $preCheck,
        $postCheck,
        [string]$Path = ""
    )

    $differences = @()

    # Get all unique properties from both objects
    $preProps = if ($preCheck) { $preCheck | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name } else { @() }
    $postProps = if ($postCheck) { $postCheck | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name } else { @() }
    $allProps = ($preProps + $postProps) | Sort-Object -Unique

    foreach ($prop in $allProps) {
        $currentPath = if ($Path) { "$Path.$prop" } else { $prop }
        $val1 = if ($preCheck) { $preCheck.$prop } else { $null }
        $val2 = if ($postCheck) { $postCheck.$prop } else { $null }

        if ($null -eq $val1 -and $null -eq $val2) { continue }

        if (($val1 -is [PSCustomObject]) -and ($val2 -is [PSCustomObject])) {
            # Recursive call for nested objects
            $subDiffs = Compare-Objects -preCheck $val1 -postCheck $val2 -Path $currentPath
            if ($subDiffs) {
                $differences += $subDiffs
            }
        } elseif (($val1 -is [Array]) -and ($val2 -is [Array])) {
            # Compare arrays
            if ($val1.Count -ne $val2.Count) {
                $differences += [PSCustomObject]@{
                    Property = $currentPath
                    Before   = "Array length: $($val1.Count)"
                    After    = "Array length: $($val2.Count)"
                }
            } else {
                for ($i = 0; $i -lt $val1.Count; $i++) {
                    $subDiffs = Compare-Objects -preCheck $val1[$i] -postCheck $val2[$i] -Path "$currentPath[$i]"
                    if ($subDiffs) {
                        $differences += $subDiffs
                    }
                }
            }
        } else {
            # Compare primitive values
            if ($val1 -ne $val2) {
                $differences += [PSCustomObject]@{
                    Property = $currentPath
                    Before   = $val1
                    After    = $val2
                }
            }
        }
    }

    return $differences
}

# Validate folder paths
if (-not (Test-Path $PreFolder)) {
    Write-Error "Pre-upgrade folder not found: $PreFolder"
    exit 1
}
if (-not (Test-Path $PostFolder)) {
    Write-Error "Post-upgrade folder not found: $PostFolder"
    exit 1
}

# Get JSON files from both folders
$preFiles = Get-ChildItem -Path $PreFolder -Filter "*.json" | Select-Object Name, FullName
$postFiles = Get-ChildItem -Path $PostFolder -Filter "*.json" | Select-Object Name, FullName

# Extract prefixes (part before the first '-') from filenames
$prePrefixes = $preFiles | ForEach-Object { ($_.Name -split '-')[0] } | Sort-Object -Unique
$postPrefixes = $postFiles | ForEach-Object { ($_.Name -split '-')[0] } | Sort-Object -Unique

# Check for prefix count and identify missing files
$allPrefixes = ($prePrefixes + $postPrefixes) | Sort-Object -Unique
$missingInPre = @()
$missingInPost = @()

foreach ($prefix in $allPrefixes) {
    if ($prefix -notin $prePrefixes) {
        $missingFile = $postFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -ExpandProperty Name
        $missingInPre += [PSCustomObject]@{
            Prefix = $prefix
            File   = $missingFile
            MissingIn = $PreFolder
        }
    }
    if ($prefix -notin $postPrefixes) {
        $missingFile = $preFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -ExpandProperty Name
        $missingInPost += [PSCustomObject]@{
            Prefix = $prefix
            File   = $missingFile
            MissingIn = $PostFolder
        }
    }
}

# Report missing files
if ($missingInPre.Count -gt 0 -or $missingInPost.Count -gt 0) {
    Write-Output "Prefix count mismatch detected:"
    if ($missingInPre.Count -gt 0) {
        Write-Output "Files missing in PreFolder ($PreFolder):"
        $missingInPre | Format-Table -AutoSize
    }
    if ($missingInPost.Count -gt 0) {
        Write-Output "Files missing in PostFolder ($PostFolder):"
        $missingInPost | Format-Table -AutoSize
    }
} else {
    Write-Output "Prefix count matches between folders: $($prePrefixes.Count) prefixes found."
}

# Find matching prefixes for comparison
$matchingPrefixes = $prePrefixes | Where-Object { $_ -in $postPrefixes }

if (-not $matchingPrefixes) {
    Write-Warning "No files with matching prefixes found in both folders."
    exit 0
}

# Compare files for each matching prefix
foreach ($prefix in $matchingPrefixes) {
    Write-Output "Comparing files for prefix: $prefix"

    # Get the first matching file from each folder (assuming one file per VM per folder)
    $preFile = $preFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -First 1
    $postFile = $postFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -First 1

    if (-not $preFile -or -not $postFile) {
        Write-Warning "Missing file for prefix '$prefix' in one of the folders. Skipping."
        continue
    }

    Write-Output "Comparing $($preFile.Name) with $($postFile.Name)"

    # Read the JSON files
    $beforeConfig = Get-Content -Path $preFile.FullName -Raw | ConvertFrom-Json
    $afterConfig = Get-Content -Path $postFile.FullName -Raw | ConvertFrom-Json

    # Perform comparison
    $diffs = Compare-Objects -preCheck $beforeConfig -postCheck $afterConfig

    if ($diffs.Count -eq 0) {
        Write-Output "No differences found between $($preFile.Name) and $($postFile.Name)."
    } else {
        Write-Output "Differences found for $prefix :"
        $diffs | Format-Table -AutoSize
    }
}

Write-Output "Comparison complete."