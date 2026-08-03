<#
.SYNOPSIS
    Builds the whole database using the mysql client directly. No Python.

.DESCRIPTION
    Runs every .sql file in the same order scripts/run_pipeline.py does,
    piping each one into mysql.exe. DELIMITER is understood natively by the
    client, so none of the custom parsing run_pipeline.py needs exists here.

.EXAMPLE
    .\scripts\build.ps1
    .\scripts\build.ps1 -WithTests
    .\scripts\build.ps1 -WithSecurity
    .\scripts\build.ps1 -NoSeed
#>
param(
    [switch]$NoSeed,
    [switch]$WithTests,
    [switch]$WithSecurity,
    [string]$DbHost = "127.0.0.1",
    [int]$DbPort = 3306,
    [string]$DbUser = "root"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$DbPassword = ""

# Read DB_USER / DB_PASSWORD from .env, the same file the Python side reads.
$envFile = Join-Path $RepoRoot ".env"
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            if ($Matches[1] -eq 'DB_PASSWORD') { $DbPassword = $Matches[2] }
            if ($Matches[1] -eq 'DB_USER' -and -not $PSBoundParameters.ContainsKey('DbUser')) {
                $DbUser = $Matches[2]
            }
        }
    }
}

# Locate the mysql client: PATH first, then the standard install folder.
$mysqlCommand = Get-Command mysql -ErrorAction SilentlyContinue
if ($mysqlCommand) {
    $mysqlExe = $mysqlCommand.Source
} else {
    $found = Get-ChildItem "C:\Program Files\MySQL" -Recurse -Filter "mysql.exe" `
                -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        Write-Error "mysql client not found. Install MySQL, or add mysql.exe to PATH."
        exit 1
    }
    $mysqlExe = $found.FullName
}

# Credentials go in a defaults file, not on the command line or in an env
# var, so the password never shows up in a process list.
$optionFile = New-TemporaryFile
@"
[client]
host=$DbHost
port=$DbPort
user=$DbUser
password=$DbPassword
"@ | Set-Content -Path $optionFile -Encoding ascii

function Invoke-SqlFile {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path)) {
        throw "Missing SQL file: $RelativePath"
    }
    Write-Host "==> $RelativePath"
    Get-Content -Raw $path | & $mysqlExe "--defaults-extra-file=$optionFile"
    if ($LASTEXITCODE -ne 0) {
        throw "mysql exited with code $LASTEXITCODE while running $RelativePath"
    }
}

try {
    # Folders the build writes to. Created here too, so this script also
    # works standalone on a fresh clone.
    foreach ($dir in @("logs", "data/raw", "data/staging", "data/processed", "data/samples")) {
        $full = Join-Path $RepoRoot $dir
        if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
    }

    Write-Host "--- schema, procedures, triggers, views, indexes ---"
    foreach ($f in @(
        "sql/schema/00_drop_all.sql",
        "sql/schema/01_create_database.sql",
        "sql/schema/02_business_rules.sql",
        "sql/schema/03_tables.sql",
        "sql/procedures/procedures.sql",
        "sql/triggers/triggers.sql",
        "sql/views/views.sql",
        "sql/indexes/01_indexes.sql"
    )) { Invoke-SqlFile $f }

    if (-not $NoSeed) {
        Write-Host "--- seed data ---"
        Invoke-SqlFile "sql/seed/01_sample_data.sql"
    }

    if ($WithSecurity) {
        Write-Host "--- roles and grants ---"
        Invoke-SqlFile "sql/security/01_roles_and_grants.sql"
    }

    if ($WithTests) {
        Write-Host "--- test suites ---"
        foreach ($f in @(
            "tests/00_test_helpers.sql",
            "tests/01_test_constraints.sql",
            "tests/02_test_procedures.sql",
            "tests/03_test_reconciliation.sql"
        )) { Invoke-SqlFile $f }
    }

    Write-Host "--- verification ---"
    $verifySql = @"
USE inventory_order_management;
SELECT
  (SELECT COUNT(*) FROM customers)      AS customers,
  (SELECT COUNT(*) FROM products)       AS products,
  (SELECT COUNT(*) FROM orders)         AS orders,
  (SELECT COUNT(*) FROM order_details)  AS order_lines,
  (SELECT COUNT(*) FROM inventory_logs) AS ledger_entries,
  (SELECT COUNT(*) FROM v_low_stock)    AS low_stock_products,
  (SELECT COUNT(*) FROM v_stock_reconciliation WHERE is_balanced = FALSE)
                                         AS stock_out_of_balance;
"@
    $verifySql | & $mysqlExe "--defaults-extra-file=$optionFile" --table

    $raw = $verifySql | & $mysqlExe "--defaults-extra-file=$optionFile" -N -B
    $stockOutOfBalance = [int]($raw -split "`t")[6]

    if ($stockOutOfBalance -gt 0) {
        Write-Error "Build finished, but stock does not reconcile ($stockOutOfBalance product(s))."
        exit 2
    }

    Write-Host "`nBuild finished successfully."
}
finally {
    Remove-Item $optionFile -Force -ErrorAction SilentlyContinue
}
