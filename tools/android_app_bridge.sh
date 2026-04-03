#!/usr/bin/env bash
set -euo pipefail

# Personal one-app Android bridge for macOS.
# This version is tuned for automatic setup + automatic APK install.

DEFAULT_APK_URL="https://www.apkmirror.com/wp-content/themes/APKMirror/download.php?id=8688287&key=469c435740615b5924a1d6224990def37bacc66a"
APP_PACKAGE=""
APP_ACTIVITY=""
APK_URL="$DEFAULT_APK_URL"
AUTO_YES=1
BRIDGE_DIR_DEFAULT="$HOME/AndroidBridge"
BRIDGE_DIR="$BRIDGE_DIR_DEFAULT"
REMOTE_UPLOAD_DIR="/sdcard/Download/BridgeUpload"
REMOTE_DOWNLOAD_DIR="/sdcard/Download/BridgeDownload"
SCRCPY_ARGS=(--stay-awake --max-size=1920)

usage() {
  cat <<USAGE
Personal Android App Bridge (macOS)

Usage:
  $0 [options] [-- <extra scrcpy args>]

Default behavior:
  - Automatically installs Homebrew/tools if missing
  - Automatically downloads and installs your app from:
    $DEFAULT_APK_URL

Options:
  --package <package>        Force package name (skip autodetect)
  --activity <activity>      Activity name (example: .MainActivity)
  --apk-url <url>            Override default APK URL
  --no-apk-install           Skip APK download/install step
  --bridge-dir <path>        Local folder for file sync (default: $BRIDGE_DIR_DEFAULT)
  --ask                      Ask before install actions
  --help, -h                 Show this help

Examples:
  $0
  $0 --no-apk-install
  $0 --package com.example.app
USAGE
}

log() { printf '\n==> %s\n' "$1"; }
warn() { printf 'Warning: %s\n' "$1" >&2; }
fatal() { printf 'Error: %s\n' "$1" >&2; exit 1; }

confirm() {
  local prompt="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

install_homebrew_if_missing() {
  if need_cmd brew; then
    return 0
  fi

  log "Homebrew is not installed"
  if ! confirm "Install Homebrew automatically now?"; then
    fatal "Homebrew is required. Re-run after installing it: https://brew.sh"
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  need_cmd brew || fatal "Homebrew install completed but 'brew' still not available in PATH. Open a new Terminal and retry."
}

install_dependencies_if_missing() {
  local missing=()
  need_cmd adb || missing+=(android-platform-tools)
  need_cmd scrcpy || missing+=(scrcpy)

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  log "Installing missing tools: ${missing[*]}"
  if ! confirm "Continue with Homebrew install?"; then
    fatal "Cannot continue without required tools."
  fi

  brew update
  brew install "${missing[@]}"

  need_cmd adb || fatal "adb is still missing after installation."
  need_cmd scrcpy || fatal "scrcpy is still missing after installation."
}

wait_for_device() {
  log "Checking Android device connection"
  adb start-server >/dev/null

  echo "Enable Developer Options + USB debugging, then connect Android by USB."
  echo "Waiting for one connected device..."

  local device_id=""
  while true; do
    device_id="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    if [[ -n "$device_id" ]]; then
      echo "Connected device: $device_id"
      break
    fi
    sleep 2
  done
}

list_third_party_packages() {
  adb shell pm list packages -3 | sed 's/^package://' | sort
}

autodetect_new_package() {
  local before_file after_file
  before_file="$(mktemp)"
  after_file="$(mktemp)"

  list_third_party_packages > "$before_file"

  log "Downloading APK"
  local tmp_apk
  tmp_apk="$(mktemp -t bridge_app_XXXXXX.apk)"
  curl -fL "$APK_URL" -o "$tmp_apk"

  log "Installing APK"
  adb install -r "$tmp_apk" >/dev/null || {
    rm -f "$tmp_apk" "$before_file" "$after_file"
    fatal "APK install failed."
  }

  rm -f "$tmp_apk"

  list_third_party_packages > "$after_file"

  local new_pkg
  new_pkg="$(comm -13 "$before_file" "$after_file" | head -n 1 || true)"

  rm -f "$before_file" "$after_file"

  if [[ -n "$new_pkg" ]]; then
    APP_PACKAGE="$new_pkg"
    log "Detected newly installed package: $APP_PACKAGE"
    return 0
  fi

  warn "Could not auto-detect new package after install."
  return 1
}

install_apk_if_enabled() {
  if [[ -z "$APK_URL" ]]; then
    return 0
  fi

  autodetect_new_package || true
}

choose_package_interactively_if_needed() {
  if [[ -n "$APP_PACKAGE" ]]; then
    return 0
  fi

  log "Package not set; choosing interactively"
  local packages
  packages="$(list_third_party_packages)"
  if [[ -z "$packages" ]]; then
    fatal "No third-party packages found on the device."
  fi

  echo "Installed app packages:"
  echo "$packages" | nl -w2 -s'. '
  echo
  read -r -p "Paste the package name to launch: " APP_PACKAGE
  [[ -n "$APP_PACKAGE" ]] || fatal "Package name is required."
}

prepare_bridge_folders() {
  mkdir -p "$BRIDGE_DIR/upload" "$BRIDGE_DIR/download"

  log "Preparing device folders"
  adb shell "mkdir -p '$REMOTE_UPLOAD_DIR' '$REMOTE_DOWNLOAD_DIR'" >/dev/null

  log "Uploading files from: $BRIDGE_DIR/upload"
  if compgen -G "$BRIDGE_DIR/upload/*" >/dev/null; then
    adb push "$BRIDGE_DIR/upload/." "$REMOTE_UPLOAD_DIR/"
  else
    echo "No files found to upload (this is okay)."
  fi

  log "Downloading files from: $REMOTE_DOWNLOAD_DIR"
  adb pull "$REMOTE_DOWNLOAD_DIR/." "$BRIDGE_DIR/download/" >/dev/null 2>&1 || true

  echo "Local upload folder:   $BRIDGE_DIR/upload"
  echo "Local download folder: $BRIDGE_DIR/download"
}

launch_app() {
  log "Launching app"
  if [[ -n "$APP_ACTIVITY" ]]; then
    adb shell am start -n "$APP_PACKAGE/$APP_ACTIVITY" >/dev/null || fatal "Failed to launch $APP_PACKAGE/$APP_ACTIVITY"
  else
    adb shell monkey -p "$APP_PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null || fatal "Failed to launch package $APP_PACKAGE"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --package) APP_PACKAGE="${2:-}"; shift 2 ;;
      --activity) APP_ACTIVITY="${2:-}"; shift 2 ;;
      --apk-url) APK_URL="${2:-}"; shift 2 ;;
      --no-apk-install) APK_URL=""; shift ;;
      --bridge-dir) BRIDGE_DIR="${2:-}"; shift 2 ;;
      --ask) AUTO_YES=0; shift ;;
      --help|-h) usage; exit 0 ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          SCRCPY_ARGS=("$@")
        fi
        break
        ;;
      *)
        fatal "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    warn "This script is optimized for macOS."
  fi

  install_homebrew_if_missing
  install_dependencies_if_missing
  wait_for_device
  install_apk_if_enabled
  choose_package_interactively_if_needed
  prepare_bridge_folders
  launch_app

  log "Starting control window"
  exec scrcpy "${SCRCPY_ARGS[@]}"
}

main "$@"
