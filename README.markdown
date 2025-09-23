# Azure VM Configuration Comparison Script

## Overview
This PowerShell script (`vm-diff.ps1`) compares Azure VM configuration JSON files between two folders, identifying missing files and differences in content for matching filenames. It provides a detailed report of discrepancies, including missing files and line-by-line differences for files present in both folders.

## Prerequisites
- **PowerShell**: Version 5.1 or later (compatible with Windows PowerShell or PowerShell Core).
- **Operating System**: Windows, Linux, or macOS with PowerShell installed.
- **Access**: Read access to the folders containing the JSON files to compare.

## Usage
Run the script from a PowerShell terminal, providing the paths to the two folders containing the JSON files.

### Syntax
```powershell
.\vm-diff.ps1 -PreFolder <path-to-pre-folder> -PostFolder <path-to-post-folder> [-Filter <file-pattern>]
```

### Parameters
- `-PreFolder` (Required): Path to the folder containing the "before" JSON files.
- `-PostFolder` (Required): Path to the folder containing the "after" JSON files.
- `-Filter` (Optional): File pattern to compare (default: `*.json`).

### Example
```powershell
.\vm-diff.ps1 -PreFolder "C:\Configs\Before" -PostFolder "C:\Configs\After"
```

This compares all `.json` files in the `Before` and `After` folders, reporting missing files and differences.

## Output
The script produces the following outputs:
1. **Missing Files**: Lists files present in one folder but not the other, with details on which folder is missing the file.
2. **Differences**: For files present in both folders, displays line-by-line differences, including line numbers and content (`Before` vs. `After`).
3. **Summary**: If no differences are found in files present in both folders and no files are missing, outputs: "All files are showing no differences." If files are missing but no content differences exist, outputs: "No content differences in files present on both sides."

### Example Output
```
WARNING: Missing files detected between folders:

FileName        Location            PrePath                     PostPath
--------        --------            -------                     --------
vm1.json        PreFolder missing   null                        C:\Configs\After\vm1.json
vm2.json        PostFolder missing  C:\Configs\Before\vm2.json  null

Differences found in the following files:
--------------------------------------------------------------------------------
Comparing:
  Pre : C:\Configs\Before\vm3.json
  Post: C:\Configs\After\vm3.json

LineNumber Before                    After
---------- ------                    -----
1          {"vmSize": "Standard_D2"} {"vmSize": "Standard_D4"}

Comparison complete.
```

## Features
- **File Comparison**: Compares files with identical names in both folders.
- **Missing File Detection**: Identifies files present in one folder but not the other.
- **Line-by-Line Differences**: Reports only the lines that differ between matching files.
- **Efficient Output**: Summarizes results, avoiding clutter when no differences are found.
- **Flexible Filtering**: Allows customization of the file pattern (e.g., `*.json`) via the `-Filter` parameter.

## Notes
- The script uses `LiteralPath` to handle paths with special characters accurately.
- File comparisons are case-sensitive and line-based, suitable for JSON configuration files.
- Ensure both folders are accessible and contain valid JSON files to avoid errors.
