# PowerShell script to compare Azure VM configuration JSON files with matching prefixes
# in two different folders, verify prefix count, report missing files, and output differing lines
# only for files with differences. If no differences are found across all files, output a single message.

param (
    [Parameter(Mandatory=$true)]
    [string]$PreFolder,

    [Parameter(Mandatory=$true)]
    [string]$PostFolder
)

# Function to compare two files line-by-line and return differences
function Compare-FileLines {
    param (
        [string]$PreFilePath,
        [string]$PostFilePath
    )

    $differences = @()

    # Read files as arrays of lines
    $preLines = Get-Content -Path $PreFilePath
    $postLines = Get-Content -Path $PostFilePath

    # Get the maximum number of lines to compare
    $maxLines = [Math]::Max($preLines.Count, $postLines.Count)

    # Compare each line
    for ($i = 0; $i -lt $maxLines; $i++) {
        $preLine = if ($i -lt $preLines.Count) { $preLines[$i] } else { "<EOF>" }
        $postLine = if ($i -lt $postLines.Count) { $postLines[$i] } else { "<EOF>" }

        if ($preLine -ne $postLine) {
            $differences += [PSCustomObject]@{
                LineNumber = $i + 1
                Before     = $preLine
                After      = $postLine
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

# Track if any differences were found
$hasDifferences = $false
$allDiffs = @()

# Compare files for each matching prefix
foreach ($prefix in $matchingPrefixes) {
    # Get the first matching file from each folder (assuming one file per VM per folder)
    $preFile = $preFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -First 1
    $postFile = $postFiles | Where-Object { $_.Name -like "$prefix-*.json" } | Select-Object -First 1

    if (-not $preFile -or -not $postFile) {
        Write-Warning "Missing file for prefix '$prefix' in one of the folders. Skipping."
        continue
    }

    # Compare files line-by-line
    $diffs = Compare-FileLines -PreFilePath $preFile.FullName -PostFilePath $postFile.FullName

    if ($diffs.Count -gt 0) {
        $hasDifferences = $true
        $allDiffs += [PSCustomObject]@{
            Prefix = $prefix
            PreFile = $preFile.Name
            PostFile = $postFile.Name
            Differences = $diffs
        }
    }
}

# Output results
if ($hasDifferences) {
    Write-Output "Differences found in the following files:"
    foreach ($diff in $allDiffs) {
        Write-Output "Comparing $($diff.PreFile) with $($diff.PostFile) for prefix: $($diff.Prefix)"
        $diff.Differences | Format-Table LineNumber, @{Label="Before";Expression={$_.Before}}, @{Label="After";Expression={$_.After}} -AutoSize
    }
} else {
    Write-Output "All files are showing no differences."
}

Write-Output "Comparison complete."