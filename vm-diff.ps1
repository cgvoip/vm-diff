# PowerShell script to compare two Azure VM configuration JSON files and output differences.

param (
    [Parameter(Mandatory=$true)]
    [string]$preFilePath,

    [Parameter(Mandatory=$true)]
    [string]$postFilePath
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
            $subDiffs = Compare-Objects -Obj1 $val1 -Obj2 $val2 -Path $currentPath
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
                    $subDiffs = Compare-Objects -Obj1 $val1[$i] -Obj2 $val2[$i] -Path "$currentPath[$i]"
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

# Read the JSON files
if (-not (Test-Path $preFilePath)) {
    Write-Error "Before file not found: $preFilePath"
    exit 1
}
if (-not (Test-Path $postFilePath)) {
    Write-Error "After file not found: $postFilePath"
    exit 1
}

$beforeConfig = Get-Content -Path $preFilePath -Raw | ConvertFrom-Json
$afterConfig = Get-Content -Path $postFilePath -Raw | ConvertFrom-Json

# Perform comparison
$diffs = Compare-Objects -Obj1 $beforeConfig -Obj2 $afterConfig

if ($diffs.Count -eq 0) {
    Write-Output "No differences found between $preFilePath and $postFilePath."
} else {
    Write-Output "Differences found:"
    $diffs | Format-Table -AutoSize
}