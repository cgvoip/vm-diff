# PowerShell script to compare Azure VM configuration JSON files by exact filename
# in two different folders, report files missing on either side, and print
# differing lines only for files with differences. If no differences are found
# across all files, output a single message.
param (
    [Parameter(Mandatory = $true)]
    [string]$PreFolder,

    [Parameter(Mandatory = $true)]
    [string]$PostFolder,

    [Parameter(Mandatory = $false)]
    [string]$Filter = '*.json'  # File pattern to compare
)

#-------------------------------
# Helpers
#-------------------------------
function Compare-FileLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PreFilePath,
        [Parameter(Mandatory = $true)][string]$PostFilePath
    )

    if (!(Test-Path -LiteralPath $PreFilePath)) {
        throw "Pre file not found: $PreFilePath"
    }
    if (!(Test-Path -LiteralPath $PostFilePath)) {
        throw "Post file not found: $PostFilePath"
    }

    $preLines  = Get-Content -LiteralPath $PreFilePath
    $postLines = Get-Content -LiteralPath $PostFilePath

    $max = [Math]::Max($preLines.Count, $postLines.Count)
    $diffs = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $max; $i++) {
        $before = if ($i -lt $preLines.Count)  { $preLines[$i] }  else { '' }
        $after  = if ($i -lt $postLines.Count) { $postLines[$i] } else { '' }
        if ($before -ne $after) {
            $diffs.Add([PSCustomObject]@{
                LineNumber = $i + 1
                Before     = $before
                After      = $after
            })
        }
    }
    return $diffs
}

#-------------------------------
# Validate inputs
#-------------------------------
if (!(Test-Path -LiteralPath $PreFolder -PathType Container)) {
    throw "PreFolder not found or not a directory: $PreFolder"
}
if (!(Test-Path -LiteralPath $PostFolder -PathType Container)) {
    throw "PostFolder not found or not a directory: $PostFolder"
}

# Gather files (by name) from each folder
$preFiles  = Get-ChildItem -LiteralPath $PreFolder -File -Filter $Filter
$postFiles = Get-ChildItem -LiteralPath $PostFolder -File -Filter $Filter

# Build filename sets
$preNames  = $preFiles.Name
$postNames = $postFiles.Name
$allNames  = ($preNames + $postNames) | Sort-Object -Unique

$missing   = New-Object System.Collections.Generic.List[object]
$allDiffs  = New-Object System.Collections.Generic.List[object]
$hasDifferences = $false

# Report files missing on either side
foreach ($name in $allNames) {
    $inPre  = $preNames -contains $name
    $inPost = $postNames -contains $name

    if (-not $inPre) {
        $missing.Add([PSCustomObject]@{
            FileName  = $name
            Location  = 'PreFolder missing'
            PrePath   = $null
            PostPath  = (Join-Path -Path $PostFolder -ChildPath $name)
        })
        continue
    }
    if (-not $inPost) {
        $missing.Add([PSCustomObject]@{
            FileName  = $name
            Location  = 'PostFolder missing'
            PrePath   = (Join-Path -Path $PreFolder -ChildPath $name)
            PostPath  = $null
        })
        continue
    }

    # Present in both -> compare
    $prePath  = (Join-Path -Path $PreFolder  -ChildPath $name)
    $postPath = (Join-Path -Path $PostFolder -ChildPath $name)

    $fileDiffs = Compare-FileLines -PreFilePath $prePath -PostFilePath $postPath

    if ($fileDiffs.Count -gt 0) {
        $hasDifferences = $true
        $allDiffs.Add([PSCustomObject]@{
            FileName    = $name
            PreFile     = $prePath
            PostFile    = $postPath
            Differences = $fileDiffs
        })
    }
}

#-------------------------------
# Output
#-------------------------------
if ($missing.Count -gt 0) {
    Write-Warning "Missing files detected between folders:"
    $missing | Sort-Object FileName, Location | Format-Table -AutoSize
    ''
}

if ($hasDifferences) {
    Write-Output "Differences found in the following files:"
    foreach ($diff in $allDiffs | Sort-Object FileName) {
        Write-Output ('-' * 80)
        Write-Output "Comparing:`n  Pre : $($diff.PreFile)`n  Post: $($diff.PostFile)"
        $diff.Differences | Format-Table LineNumber, @{Label='Before';Expression={$_.Before}}, @{Label='After';Expression={$_.After}} -AutoSize
        ''
    }
} else {
    if ($missing.Count -eq 0) {
        Write-Output "All files are showing no differences."
    } else {
        Write-Output "No content differences in files present on both sides."
    }
}

Write-Output "Comparison complete."
