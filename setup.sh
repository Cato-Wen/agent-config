#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# OpenCode Agent Config Setup Script
# Works on: macOS, Linux, Windows (Git Bash / MSYS2 / WSL)
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_SRC="$SCRIPT_DIR/.opencode"

# ── Colors (auto-disable when not a terminal) ──
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; CYAN=''; NC=''
fi

info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
ask()   { printf "${CYAN}[?]${NC}    %s" "$1"; }

# ── Detect OS ──
IS_WINDOWS=false
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
esac

# ── Detect shell profile ──
detect_shell_profile() {
  case "${SHELL:-}" in
    */zsh)  echo "${HOME}/.zshrc" ;;
    */bash) echo "${HOME}/.bashrc" ;;
    *)
      # Fallback: check common files
      if [ -f "${HOME}/.zshrc" ]; then
        echo "${HOME}/.zshrc"
      elif [ -f "${HOME}/.bashrc" ]; then
        echo "${HOME}/.bashrc"
      elif [ -f "${HOME}/.profile" ]; then
        echo "${HOME}/.profile"
      else
        echo "${HOME}/.bashrc"
      fi
      ;;
  esac
}

# ── Convert MSYS/Git Bash path to Windows native path ──
to_win_path() {
  if command -v cygpath > /dev/null 2>&1; then
    cygpath -w "$1"
  else
    # Manual conversion: /c/Users/... -> C:\Users\...
    echo "$1" | sed -e 's|^/\([a-zA-Z]\)/|\1:\\|' -e 's|/|\\|g'
  fi
}

# ── Set Windows system-level user environment variable ──
win_setenv() {
  local var_name="$1"
  local var_value="$2"

  # Use PowerShell to set persistent user-level env var
  if command -v powershell.exe > /dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "[Environment]::SetEnvironmentVariable('$var_name', '$var_value', 'User')" 2>/dev/null
    if [ $? -ne 0 ]; then return 1; fi
    # Verify by reading back
    win_verify_env "$var_name" "$var_value" && return 0
    return 1
  fi

  # Fallback to setx (truncates at 1024 chars, but fine for these values)
  if command -v setx.exe > /dev/null 2>&1; then
    setx.exe "$var_name" "$var_value" > /dev/null 2>&1
    if [ $? -ne 0 ]; then return 1; fi
    win_verify_env "$var_name" "$var_value" && return 0
    return 1
  fi

  return 1
}

# ── Verify a Windows user env var was persisted correctly ──
win_verify_env() {
  local var_name="$1"
  local expected="$2"

  if command -v powershell.exe > /dev/null 2>&1; then
    local actual
    actual="$(powershell.exe -NoProfile -Command \
      "[Environment]::GetEnvironmentVariable('$var_name', 'User')" 2>/dev/null | tr -d '\r')"
    if [ "$actual" = "$expected" ]; then
      return 0
    else
      warn "Verify failed for $var_name: expected '$expected', got '$actual'"
      return 1
    fi
  fi

  # No way to verify without PowerShell, assume success
  return 0
}

# ══════════════════════════════════════════════
# Part 1: Google Vertex AI Environment Variables
# ══════════════════════════════════════════════

setup_env() {
  echo ""
  echo "══════════════════════════════════════════"
  echo "  Step 1: Google Vertex AI Configuration"
  echo "══════════════════════════════════════════"
  echo ""

  # ── GOOGLE_CLOUD_PROJECT ──
  local current_project="${GOOGLE_CLOUD_PROJECT:-}"
  if [ -n "$current_project" ]; then
    info "Current GOOGLE_CLOUD_PROJECT: $current_project"
    ask "Press Enter to keep, or type a new value: "
    read -r input_project
    [ -z "$input_project" ] && input_project="$current_project"
  else
    ask "GOOGLE_CLOUD_PROJECT (your GCP project ID): "
    read -r input_project
    if [ -z "$input_project" ]; then
      error "GOOGLE_CLOUD_PROJECT is required."
      exit 1
    fi
  fi

  # ── GOOGLE_APPLICATION_CREDENTIALS ──
  local current_creds="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  if [ -n "$current_creds" ]; then
    info "Current GOOGLE_APPLICATION_CREDENTIALS: $current_creds"
    ask "Press Enter to keep, or type a new path: "
    read -r input_creds
    [ -z "$input_creds" ] && input_creds="$current_creds"
  else
    echo ""
    info "Authentication options:"
    echo "  1) Provide a service account JSON key file path"
    echo "  2) Use gcloud CLI (run: gcloud auth application-default login)"
    echo ""
    ask "Path to service account JSON: "
    read -r input_creds
  fi

  # ── Validate credentials file ──
  if [ -n "$input_creds" ] && [ "$input_creds" != "gcloud" ]; then
    # Normalize path on Windows (convert backslashes)
    input_creds="${input_creds//\\//}"
    if [ ! -f "$input_creds" ]; then
      warn "File not found: $input_creds"
      ask "Continue anyway? (y/N): "
      read -r confirm
      case "$confirm" in
        [yY]*) ;;
        *) error "Aborted."; exit 1 ;;
      esac
    fi
  fi

  # ── Persist environment variables ──

  # -- Windows: write user env vars to registry --
  if $IS_WINDOWS; then
    echo ""
    info "Writing environment variables to Windows registry..."

    local win_creds_path=""
    if [ -n "$input_creds" ] && [ "$input_creds" != "gcloud" ]; then
      win_creds_path="$(to_win_path "$input_creds")"
    fi

    local win_fail=0

    if win_setenv "GOOGLE_CLOUD_PROJECT" "$input_project"; then
      info "  GOOGLE_CLOUD_PROJECT = $input_project (verified)"
    else
      error "  GOOGLE_CLOUD_PROJECT - write or verify failed"
      win_fail=$((win_fail + 1))
    fi

    if win_setenv "VERTEX_LOCATION" "global"; then
      info "  VERTEX_LOCATION = global (verified)"
    else
      error "  VERTEX_LOCATION - write or verify failed"
      win_fail=$((win_fail + 1))
    fi

    if [ -n "$win_creds_path" ]; then
      if win_setenv "GOOGLE_APPLICATION_CREDENTIALS" "$win_creds_path"; then
        info "  GOOGLE_APPLICATION_CREDENTIALS = $win_creds_path (verified)"
      else
        error "  GOOGLE_APPLICATION_CREDENTIALS - write or verify failed"
        win_fail=$((win_fail + 1))
      fi
    fi

    echo ""
    if [ "$win_fail" -eq 0 ]; then
      info "All environment variables set and verified."
    else
      warn "$win_fail variable(s) failed. Check manually:"
      warn "  System Settings > Environment Variables"
      warn "  Or run in PowerShell: [Environment]::GetEnvironmentVariable('VAR_NAME', 'User')"
    fi
  fi

  # -- Shell profile: write for bash/zsh (macOS / Linux only) --
  if ! $IS_WINDOWS; then
  local shell_profile
  shell_profile="$(detect_shell_profile)"

  ask "Write to shell profile? [$shell_profile] (Y/n): "
  read -r write_confirm

  case "$write_confirm" in [nN]*) ;; *)
    # Ask for custom profile path
    ask "Press Enter to use $shell_profile, or type a custom path: "
    read -r custom_profile
    [ -n "$custom_profile" ] && shell_profile="$custom_profile"

    # Remove old entries
    if [ -f "$shell_profile" ]; then
      local tmp_file="${shell_profile}.agent-config.tmp"
      grep -v '# agent-config: vertex-ai' "$shell_profile" > "$tmp_file" 2>/dev/null || true
      mv "$tmp_file" "$shell_profile"
    fi

    # Append new entries
    {
      echo ""
      echo "# agent-config: vertex-ai"
      echo "export GOOGLE_CLOUD_PROJECT=\"$input_project\"  # agent-config: vertex-ai"
      if [ -n "$input_creds" ] && [ "$input_creds" != "gcloud" ]; then
        echo "export GOOGLE_APPLICATION_CREDENTIALS=\"$input_creds\"  # agent-config: vertex-ai"
      fi
      echo "export VERTEX_LOCATION=\"global\"  # agent-config: vertex-ai"
    } >> "$shell_profile"

    # Verify shell profile was written correctly
    local verify_ok=true
    grep -q "GOOGLE_CLOUD_PROJECT=\"$input_project\"" "$shell_profile" 2>/dev/null || verify_ok=false
    grep -q "VERTEX_LOCATION=\"global\"" "$shell_profile" 2>/dev/null || verify_ok=false
    if [ -n "$input_creds" ] && [ "$input_creds" != "gcloud" ]; then
      grep -q "GOOGLE_APPLICATION_CREDENTIALS=\"$input_creds\"" "$shell_profile" 2>/dev/null || verify_ok=false
    fi

    if $verify_ok; then
      info "Written to $shell_profile (verified)"
    else
      warn "Written to $shell_profile but verification failed. Please check the file manually."
    fi
  ;; esac
  fi

  # Export for current session
  export GOOGLE_CLOUD_PROJECT="$input_project"
  [ -n "$input_creds" ] && [ "$input_creds" != "gcloud" ] && export GOOGLE_APPLICATION_CREDENTIALS="$input_creds"
  export VERTEX_LOCATION="global"

  info "Environment variables set for current session."
  echo ""
}

# ══════════════════════════════════════════════
# Part 2: Merge .opencode directory
# ══════════════════════════════════════════════

merge_opencode() {
  echo "══════════════════════════════════════════"
  echo "  Step 2: Deploy .opencode Configuration"
  echo "══════════════════════════════════════════"
  echo ""

  if [ ! -d "$OPENCODE_SRC" ]; then
    error "Source .opencode directory not found at: $OPENCODE_SRC"
    exit 1
  fi

  ask "Target project directory (where .opencode should be deployed): "
  read -r target_dir

  if [ -z "$target_dir" ]; then
    error "Target directory is required."
    exit 1
  fi

  # Normalize path (handle Windows backslashes and trailing slash)
  target_dir="${target_dir//\\//}"
  target_dir="${target_dir%/}"

  if [ ! -d "$target_dir" ]; then
    error "Directory does not exist: $target_dir"
    exit 1
  fi

  local target_opencode="$target_dir/.opencode"

  if [ -d "$target_opencode" ]; then
    warn "Target already has .opencode directory."
    info "Merging: new files will be added, existing files will be updated."
    echo ""

    # Show what will change
    local changes=0
    while IFS= read -r -d '' src_file; do
      local rel_path="${src_file#$OPENCODE_SRC/}"
      local dst_file="$target_opencode/$rel_path"

      if [ ! -f "$dst_file" ]; then
        echo "  + (new)     $rel_path"
        changes=$((changes + 1))
      elif ! diff -q "$src_file" "$dst_file" > /dev/null 2>&1; then
        echo "  ~ (update)  $rel_path"
        changes=$((changes + 1))
      fi
    done < <(find "$OPENCODE_SRC" -type f -print0)

    if [ "$changes" -eq 0 ]; then
      info "Already up to date. No changes needed."
      return
    fi

    echo ""
    ask "Apply these changes? (Y/n): "
    read -r merge_confirm
    case "$merge_confirm" in
      [nN]*) info "Skipped."; return ;;
    esac

    # Merge: opencode.json needs special handling
    if [ -f "$OPENCODE_SRC/opencode.json" ] && [ -f "$target_opencode/opencode.json" ]; then
      merge_opencode_json "$OPENCODE_SRC/opencode.json" "$target_opencode/opencode.json"
    fi

    # Copy all other files (skip opencode.json, handled above)
    while IFS= read -r -d '' src_file; do
      local rel_path="${src_file#$OPENCODE_SRC/}"
      [ "$rel_path" = "opencode.json" ] && continue
      local dst_file="$target_opencode/$rel_path"
      local dst_dir
      dst_dir="$(dirname "$dst_file")"
      mkdir -p "$dst_dir"
      cp "$src_file" "$dst_file"
    done < <(find "$OPENCODE_SRC" -type f -print0)

  else
    info "No existing .opencode found. Copying entire directory."
    cp -r "$OPENCODE_SRC" "$target_opencode"
  fi

  info "Done! .opencode deployed to: $target_opencode"
  echo ""
}

# ── Merge opencode.json (combine MCP configs) ──
merge_opencode_json() {
  local src_json="$1"
  local dst_json="$2"

  # Try using node (available on most systems)
  if command -v node > /dev/null 2>&1; then
    node -e "
      const src = JSON.parse(require('fs').readFileSync('$src_json', 'utf8'));
      const dst = JSON.parse(require('fs').readFileSync('$dst_json', 'utf8'));

      // Deep merge: src entries override dst, but dst-only entries are kept
      function merge(target, source) {
        for (const key in source) {
          if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])
              && target[key] && typeof target[key] === 'object' && !Array.isArray(target[key])) {
            merge(target[key], source[key]);
          } else {
            target[key] = source[key];
          }
        }
        return target;
      }

      const merged = merge(dst, src);
      require('fs').writeFileSync('$dst_json', JSON.stringify(merged, null, 2) + '\n');
    " 2>/dev/null && {
      info "Merged opencode.json (existing MCP configs preserved)"
      return
    }
  fi

  # Try using python3 / python
  local python_cmd=""
  if command -v python3 > /dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python > /dev/null 2>&1; then
    python_cmd="python"
  fi

  if [ -n "$python_cmd" ]; then
    "$python_cmd" -c "
import json, sys

def merge(dst, src):
    for k, v in src.items():
        if k in dst and isinstance(dst[k], dict) and isinstance(v, dict):
            merge(dst[k], v)
        else:
            dst[k] = v
    return dst

with open('$src_json') as f: src = json.load(f)
with open('$dst_json') as f: dst = json.load(f)
merged = merge(dst, src)
with open('$dst_json', 'w') as f: json.dump(merged, f, indent=2); f.write('\n')
" 2>/dev/null && {
      info "Merged opencode.json (existing MCP configs preserved)"
      return
    }
  fi

  # Fallback: overwrite with warning
  warn "Neither node nor python available. Overwriting opencode.json."
  cp "$src_json" "$dst_json"
}

# ══════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════

main() {
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║   OpenCode Agent Config Setup            ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  setup_env
  merge_opencode

  echo "══════════════════════════════════════════"
  echo "  Setup Complete!"
  echo "══════════════════════════════════════════"
  echo ""
  info "Next steps:"
  if $IS_WINDOWS; then
    echo "  1. Open a NEW terminal window (so Windows env vars take effect)"
  else
    echo "  1. Restart your terminal (or run: source $(detect_shell_profile))"
  fi
  echo "  2. cd into your target project"
  echo "  3. Run: opencode"
  echo "  4. First time MCP auth: opencode mcp auth atlassian"
  echo ""
}

main "$@"
