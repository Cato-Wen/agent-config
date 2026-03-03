#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------
# OpenCode Agent Config Setup Script (PowerShell)
# Works on: Windows PowerShell 5.1+, PowerShell 7+
# ---------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$OpencodeSrc = Join-Path $ScriptDir ".opencode"

# -- Output helpers --
function Write-Info  ($msg) { Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Write-Warn  ($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err   ($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Read-Ask    ($msg) { Write-Host "[?]    $msg" -ForegroundColor Cyan -NoNewline; return Read-Host }

# ==============================================
# Part 1: Google Vertex AI Environment Variables
# ==============================================

function Setup-Env {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  Step 1: Google Vertex AI Configuration"
    Write-Host "=========================================="
    Write-Host ""

    # -- GOOGLE_CLOUD_PROJECT --
    $currentProject = [Environment]::GetEnvironmentVariable("GOOGLE_CLOUD_PROJECT", "User")
    if ($currentProject) {
        Write-Info "Current GOOGLE_CLOUD_PROJECT: $currentProject"
        $inputProject = Read-Ask "Press Enter to keep, or type a new value: "
        if ([string]::IsNullOrWhiteSpace($inputProject)) { $inputProject = $currentProject }
    } else {
        $inputProject = Read-Ask "GOOGLE_CLOUD_PROJECT (your GCP project ID): "
        if ([string]::IsNullOrWhiteSpace($inputProject)) {
            Write-Err "GOOGLE_CLOUD_PROJECT is required."
            exit 1
        }
    }

    # -- GOOGLE_APPLICATION_CREDENTIALS --
    $currentCreds = [Environment]::GetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", "User")
    if ($currentCreds) {
        Write-Info "Current GOOGLE_APPLICATION_CREDENTIALS: $currentCreds"
        $inputCreds = Read-Ask "Press Enter to keep, or type a new path: "
        if ([string]::IsNullOrWhiteSpace($inputCreds)) { $inputCreds = $currentCreds }
    } else {
        Write-Host ""
        Write-Info "Authentication options:"
        Write-Host "  1) Provide a service account JSON key file path"
        Write-Host "  2) Use gcloud CLI (run: gcloud auth application-default login)"
        Write-Host ""
        $inputCreds = Read-Ask "Path to service account JSON: "
    }

    # -- Validate credentials file --
    if (-not [string]::IsNullOrWhiteSpace($inputCreds)) {
        if (-not (Test-Path $inputCreds)) {
            Write-Warn "File not found: $inputCreds"
            $confirm = Read-Ask "Continue anyway? (y/N): "
            if ($confirm -notmatch '^[yY]') {
                Write-Err "Aborted."
                exit 1
            }
        }
    }

    # -- Write to Windows registry (user-level) --
    Write-Host ""
    Write-Info "Writing environment variables to Windows registry..."

    $failCount = 0

    # GOOGLE_CLOUD_PROJECT
    try {
        [Environment]::SetEnvironmentVariable("GOOGLE_CLOUD_PROJECT", $inputProject, "User")
        $actual = [Environment]::GetEnvironmentVariable("GOOGLE_CLOUD_PROJECT", "User")
        if ($actual -eq $inputProject) {
            Write-Info "  GOOGLE_CLOUD_PROJECT = $inputProject (verified)"
        } else {
            Write-Err "  GOOGLE_CLOUD_PROJECT - verify failed: got '$actual'"
            $failCount++
        }
    } catch {
        Write-Err "  GOOGLE_CLOUD_PROJECT - write failed: $_"
        $failCount++
    }

    # VERTEX_LOCATION
    try {
        [Environment]::SetEnvironmentVariable("VERTEX_LOCATION", "global", "User")
        $actual = [Environment]::GetEnvironmentVariable("VERTEX_LOCATION", "User")
        if ($actual -eq "global") {
            Write-Info "  VERTEX_LOCATION = global (verified)"
        } else {
            Write-Err "  VERTEX_LOCATION - verify failed: got '$actual'"
            $failCount++
        }
    } catch {
        Write-Err "  VERTEX_LOCATION - write failed: $_"
        $failCount++
    }

    # GOOGLE_APPLICATION_CREDENTIALS
    if (-not [string]::IsNullOrWhiteSpace($inputCreds)) {
        try {
            [Environment]::SetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", $inputCreds, "User")
            $actual = [Environment]::GetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", "User")
            if ($actual -eq $inputCreds) {
                Write-Info "  GOOGLE_APPLICATION_CREDENTIALS = $inputCreds (verified)"
            } else {
                Write-Err "  GOOGLE_APPLICATION_CREDENTIALS - verify failed: got '$actual'"
                $failCount++
            }
        } catch {
            Write-Err "  GOOGLE_APPLICATION_CREDENTIALS - write failed: $_"
            $failCount++
        }
    }

    Write-Host ""
    if ($failCount -eq 0) {
        Write-Info "All environment variables set and verified."
    } else {
        Write-Warn "$failCount variable(s) failed. Set them manually:"
        Write-Warn "  System Settings > Environment Variables"
    }

    # Set for current session too
    $env:GOOGLE_CLOUD_PROJECT = $inputProject
    $env:VERTEX_LOCATION = "global"
    if (-not [string]::IsNullOrWhiteSpace($inputCreds)) {
        $env:GOOGLE_APPLICATION_CREDENTIALS = $inputCreds
    }

    Write-Info "Environment variables also set for current session."
    Write-Host ""
}

# ==============================================
# Part 2: Merge .opencode directory
# ==============================================

function Merge-OpencodeJson ($srcJson, $dstJson) {
    # Deep merge: src entries override dst, dst-only entries are kept
    function Merge-Object ($target, $source) {
        foreach ($key in $source.PSObject.Properties.Name) {
            $srcVal = $source.$key
            if ($null -ne $target.PSObject.Properties[$key]) {
                $dstVal = $target.$key
                if ($srcVal -is [PSCustomObject] -and $dstVal -is [PSCustomObject]) {
                    Merge-Object $dstVal $srcVal
                } else {
                    $target.$key = $srcVal
                }
            } else {
                $target | Add-Member -NotePropertyName $key -NotePropertyValue $srcVal
            }
        }
    }

    $src = Get-Content $srcJson -Raw | ConvertFrom-Json
    $dst = Get-Content $dstJson -Raw | ConvertFrom-Json
    Merge-Object $dst $src
    $dst | ConvertTo-Json -Depth 20 | Set-Content $dstJson -Encoding UTF8
    Write-Info "Merged opencode.json (existing MCP configs preserved)"
}

function Deploy-Opencode {
    Write-Host "=========================================="
    Write-Host "  Step 2: Deploy .opencode Configuration"
    Write-Host "=========================================="
    Write-Host ""

    if (-not (Test-Path $OpencodeSrc)) {
        Write-Err "Source .opencode directory not found at: $OpencodeSrc"
        exit 1
    }

    $targetDir = Read-Ask "Target project directory (where .opencode should be deployed): "

    if ([string]::IsNullOrWhiteSpace($targetDir)) {
        Write-Err "Target directory is required."
        exit 1
    }

    $targetDir = $targetDir.TrimEnd('\', '/')
    if (-not (Test-Path $targetDir -PathType Container)) {
        Write-Err "Directory does not exist: $targetDir"
        exit 1
    }

    $targetOpencode = Join-Path $targetDir ".opencode"

    if (Test-Path $targetOpencode) {
        Write-Warn "Target already has .opencode directory."
        Write-Info "Merging: new files will be added, existing files will be updated."
        Write-Host ""

        # Show what will change
        $changes = 0
        $srcFiles = Get-ChildItem $OpencodeSrc -Recurse -File
        foreach ($srcFile in $srcFiles) {
            $relPath = $srcFile.FullName.Substring($OpencodeSrc.Length + 1)
            $dstFile = Join-Path $targetOpencode $relPath

            if (-not (Test-Path $dstFile)) {
                Write-Host "  + (new)     $relPath"
                $changes++
            } elseif ((Get-FileHash $srcFile.FullName).Hash -ne (Get-FileHash $dstFile).Hash) {
                Write-Host "  ~ (update)  $relPath"
                $changes++
            }
        }

        if ($changes -eq 0) {
            Write-Info "Already up to date. No changes needed."
            return
        }

        Write-Host ""
        $confirm = Read-Ask "Apply these changes? (Y/n): "
        if ($confirm -match '^[nN]') {
            Write-Info "Skipped."
            return
        }

        # Merge opencode.json specially
        $srcJson = Join-Path $OpencodeSrc "opencode.json"
        $dstJson = Join-Path $targetOpencode "opencode.json"
        if ((Test-Path $srcJson) -and (Test-Path $dstJson)) {
            Merge-OpencodeJson $srcJson $dstJson
        }

        # Copy all other files
        foreach ($srcFile in $srcFiles) {
            $relPath = $srcFile.FullName.Substring($OpencodeSrc.Length + 1)
            if ($relPath -eq "opencode.json") { continue }
            $dstFile = Join-Path $targetOpencode $relPath
            $dstDir = Split-Path $dstFile -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item $srcFile.FullName $dstFile -Force
        }

    } else {
        Write-Info "No existing .opencode found. Copying entire directory."
        Copy-Item $OpencodeSrc $targetOpencode -Recurse
    }

    Write-Info "Done! .opencode deployed to: $targetOpencode"
    Write-Host ""
}

# ==============================================
# Main
# ==============================================

Write-Host ""
Write-Host "+===========================================+"
Write-Host "|   OpenCode Agent Config Setup             |"
Write-Host "+===========================================+"
Write-Host ""

Setup-Env
Deploy-Opencode

Write-Host "=========================================="
Write-Host "  Setup Complete!"
Write-Host "=========================================="
Write-Host ""
Write-Info "Next steps:"
Write-Host "  1. Open a NEW terminal window (so env vars take effect)"
Write-Host "  2. cd into your target project"
Write-Host "  3. Run: opencode"
Write-Host "  4. First time MCP auth: opencode mcp auth atlassian"
Write-Host ""
