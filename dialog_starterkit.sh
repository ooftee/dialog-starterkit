#!/bin/zsh
set -euo pipefail

##########################################################################################
# Script Information
##########################################################################################
#
# Authors: Martin Piron
# Assisted by: Cursor
#
# Name:     dialog_starterkit.sh
# Version:  2.0.0 (17/08/2026)
# Repo:     https://github.com/ooftee/dialog-starterkit
#
# This script was inspired by Adam Codega's:
# https://github.com/acodega/dialog-scripts/
# Thanks to James Corcoran for his help, support and snippets:
# https://github.com/jorks
#

##########################################################################################
# General Information
##########################################################################################
#
# Dialog Starter Kit. Presents a checkbox selection dialog, then installs chosen
# apps via Jamf custom triggers while SwiftDialog Inspect Mode monitors install
# paths and shows live progress.
#
# Requires macOS 15 or newer and SwiftDialog 3.1.0 or newer.

##########################################################################################
# VARIABLES TO EDIT
##########################################################################################

# Company logo shown in dialogs (replace with your Self Service / brand icon)
  ICON="/Library/Application Support/Dialog/Dialog.app"

# Optional Support / Help URL shown on the selection and failure dialogs
  SUPPORT_URL="https://support.example.com"

# Public URL prefix for app icons (icon filename must match the Jamf trigger)
# Example: https://s3.ap-southeast-2.amazonaws.com/your-bucket/icons
  ICON_BASE_URL="https://s3.ap-southeast-2.amazonaws.com/***"

# Working directory for cached icons and logs
  MANAGEMENT_DIR="/Library/Management/Dialog-StarterKit"
  ICONS_DIR="${MANAGEMENT_DIR}/Branding/Icons"

# Apps to install format is FriendlyName,Location,Trigger
  APPS=(
    "GitHub Desktop,/Applications/GitHub Desktop.app,install_githubdesktop"
    "Icons,/Applications/Icons.app,install_icons"
    "iMazing Profile Editor,/Applications/iMazing Profile Editor.app,install_imazingprofileeditor"
    "iTerm,/Applications/iTerm.app,install_iterm"
    "Keka,/Applications/Keka.app,install_keka"
  )

##########################################################################################
# Global Variables
##########################################################################################

# User
  CURRENT_USER=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# macOS
  MACOS_VERSION=$(sw_vers -ProductVersion)
  MACOS_MAJOR=$(sw_vers -ProductVersion | cut -d '.' -f 1)

# Utility Binary Locations
  DIALOG_BINARY="/usr/local/bin/dialog"
  JAMF_BINARY="/usr/local/bin/jamf"

##########################################################################################
# Testing and Logging
##########################################################################################

  ENABLE_LOGFILE="true"
  LOGDIR="${MANAGEMENT_DIR}/Logs"

# Parameter 4: Testing Mode [ false (default) | true ]
  TESTING_MODE="${4:-false}"
  case "${TESTING_MODE}" in
    "true"|"True"|"TRUE")
      TESTING_MODE="true"
      ;;
    *)
      TESTING_MODE="false"
      ;;
  esac

##########################################################################################
# Global Functions
##########################################################################################

# Function: _echoerr, _echolog, info, warn, error, fatal
# Description: Provide Jamf-safe stderr logging, optional file logging, and severity helpers.
# Usage: info "message"; warn "message"; error "message"; fatal "message" [exit_code]
  _echoerr() { printf "%s\n" "$*" >&2 ; }
  _echolog() { if [[ "${ENABLE_LOGFILE:-false}" == "true" && -n "${LOGFILE:-}" ]]; then printf "%s %s\n" "$(date +"%F %R:%S")" "$*" >>"${LOGFILE}"; fi }
  info()     { _echoerr "[INFO ] $*" ; _echolog "[INFO ]  $*" ; }
  warn()     { _echoerr "[WARN ] $*" ; _echolog "[WARN ]  $*" ; }
  error()    { _echoerr "[ERROR] $*" ; _echolog "[ERROR]  $*" ; }
  fatal()    { _echoerr "[FATAL] $*" ; _echolog "[FATAL]  $*" ; exit "${2:-1}" ; }

  SCRIPT_NAME=$(basename "${0}")

# Function: _init, cleanup
# Description: Initialise script metadata, optional file logging, and EXIT trap reporting.
# Usage: _init; trap cleanup EXIT
  _init() {
    if [[ "${ENABLE_LOGFILE:-false}" == "true" ]]; then
      LOGFILE="${LOGDIR:-/var/tmp}/$(date +"%F_%H.%M.%S")-${SCRIPT_NAME}.log"
      [[ -n "${LOGDIR:-}" && ! -d "${LOGDIR}" ]] && mkdir -p "${LOGDIR}"
      [[ ! -f "${LOGFILE}" ]] && touch "${LOGFILE}"
    fi

    info "## Script: ${SCRIPT_NAME}"
    info "## Start : $(date +"%F %R:%S")"
    if [[ "${TESTING_MODE:-false}" == "true" ]]; then
      info "## Testing Mode: ENABLED"
    fi
  }

  cleanup() {
    local exit_code=$?

    if [[ -n "${INSPECT_PID:-}" ]] && kill -0 "${INSPECT_PID}" 2>/dev/null; then
      if [[ -n "${INSPECT_COMMAND_FILE:-}" && -f "${INSPECT_COMMAND_FILE}" ]]; then
        printf 'quit:\n' >> "${INSPECT_COMMAND_FILE}" 2>/dev/null || true
        sleep 1
      fi
      kill "${INSPECT_PID}" 2>/dev/null || true
      wait "${INSPECT_PID}" 2>/dev/null || true
    fi

    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
      rm -rf "${TEMP_DIR}" 2>/dev/null || true
    fi

    info "## Finish: $(date +"%F %R:%S")"
    info "## Exit Code: ${exit_code}"
  }

  trap cleanup EXIT
  _init

# Function: execute
# Description: Wrap destructive operations with testing-mode support. In testing
#              mode, log the command without running it. In production, run the
#              command and warn on failure. Callers decide severity via || handling.
# Usage: execute rm -f "${file}"
# Returns: 0 on success or testing mode, 1 on failure
  execute() {
    if [[ "${TESTING_MODE:-false}" == "true" ]]; then
      info "[TESTING MODE] Would execute: $*"
      return 0
    fi
    if ! "$@"; then
      warn "Failed running: $*"
      return 1
    fi
  }

# Function: require_logged_in_user
# Description: Fatal guard for scripts or functions that require a console user.
# Usage: require_logged_in_user
  require_logged_in_user() {
    if [[ -z "${CURRENT_USER:-}" || "${CURRENT_USER}" == "loginwindow" || "${CURRENT_USER}" == "_mbsetupuser" ]]; then
      fatal "No logged-in user found (CURRENT_USER=${CURRENT_USER:-empty})"
    fi
  }

# Function: is_version_at_least
# Description: Compare semantic versions.
# Usage: is_version_at_least "${current}" "1.2.3"
# Returns: 0 if target is greater than or equal to minimum, 1 otherwise
  is_version_at_least() {
    local target="${1:-}"
    local minimum="${2:-}"
    if [[ -z "${target}" || -z "${minimum}" ]]; then
      error "is_version_at_least requires two arguments: target minimum"
      return 1
    fi
    [[ "${target}" == "$(printf '%s\n%s' "${target}" "${minimum}" | sort -V | tail -n 1)" ]]
  }

# Function: is_meeting_active
# Description: Check whether Zoom or Teams appears in active power assertions.
# Usage: if is_meeting_active; then ...
# Returns: 0 if a meeting appears active, 1 otherwise
  is_meeting_active() {
    local assertions
    assertions=$(pmset -g assertions 2>/dev/null) || return 1
    if printf '%s\n' "${assertions}" | grep -qiE "zoom|teams"; then
      return 0
    fi
    return 1
  }

##########################################################################################
# Script Configuration
##########################################################################################

  SWIFTDIALOG_INSTALL_TRIGGER="install_swiftdialog"
  MIN_SWIFTDIALOG_VERSION="3.1.0"
  MIN_MACOS_MAJOR=15
  MAX_INSTALL_RETRIES=3
  ICON_DOWNLOAD_ATTEMPTS=3
  SELECTION_DIALOG_HEIGHT=450
  INSPECT_READY_WAIT_SECONDS=5
  INSPECT_AUTO_CLOSE_SECONDS=60

  TEMP_DIR=""
  SELECTION_JSON_FILE=""
  INSPECT_JSON_FILE=""
  INSPECT_COMMAND_FILE=""
  INSPECT_SESSIONS_DIR=""
  INSPECT_PID=""
  SELECTED_APPS=()
  FAILED_APPS=()

##########################################################################################
# Script Functions
##########################################################################################

# --- Prerequisites ---

# Function: require_macos_version
# Description: Fatal guard requiring macOS 15 or newer for SwiftDialog 3.
  require_macos_version() {
    if (( MACOS_MAJOR < MIN_MACOS_MAJOR )); then
      fatal "This script requires macOS ${MIN_MACOS_MAJOR} or newer. Detected: ${MACOS_VERSION}"
    fi
    info "macOS version is supported: ${MACOS_VERSION}"
  }

# Function: require_jamf_binary
# Description: Fatal guard for the Jamf binary.
  require_jamf_binary() {
    [[ -x "${JAMF_BINARY}" ]] || fatal "Jamf binary not found at ${JAMF_BINARY}"
    info "Jamf binary is available"
  }

# Function: require_dialog_icon
# Description: Fatal guard for the dialog icon path. Call after ensure_swiftdialog
#              when ICON defaults to Dialog.app.
  require_dialog_icon() {
    [[ -e "${ICON}" ]] || fatal "Dialog icon not found at ${ICON}. Set ICON to your company logo path."
    info "Dialog icon is available: ${ICON}"
  }

# Function: get_dialog_version
# Description: Return the installed SwiftDialog version string.
# Returns: Prints the version on stdout, or returns 1 when unavailable
  get_dialog_version() {
    local version=""
    if [[ ! -x "${DIALOG_BINARY}" ]]; then
      return 1
    fi
    version=$("${DIALOG_BINARY}" --version 2>/dev/null | head -n 1 | tr -d '[:space:]') || return 1
    [[ -n "${version}" ]] || return 1
    printf '%s\n' "${version}"
  }

# Function: ensure_swiftdialog
# Description: Ensure SwiftDialog 3.1.0 or newer is installed, retrying the Jamf
#              install trigger when the binary is missing or too old.
  ensure_swiftdialog() {
    local max_attempts=3
    local attempt=1
    local version=""

    while (( attempt <= max_attempts )); do
      if version=$(get_dialog_version); then
        if is_version_at_least "${version}" "${MIN_SWIFTDIALOG_VERSION}"; then
          info "SwiftDialog ${version} meets the minimum version ${MIN_SWIFTDIALOG_VERSION}"
          return 0
        fi
        warn "SwiftDialog ${version} is below ${MIN_SWIFTDIALOG_VERSION}. Running ${SWIFTDIALOG_INSTALL_TRIGGER} (attempt ${attempt}/${max_attempts})"
      else
        warn "SwiftDialog not found. Running ${SWIFTDIALOG_INSTALL_TRIGGER} (attempt ${attempt}/${max_attempts})"
      fi

      execute "${JAMF_BINARY}" policy -event "${SWIFTDIALOG_INSTALL_TRIGGER}" || true
      sleep 2
      (( attempt++ ))
    done

    version=$(get_dialog_version) || fatal "SwiftDialog not found at ${DIALOG_BINARY} after ${max_attempts} install attempts"
    if ! is_version_at_least "${version}" "${MIN_SWIFTDIALOG_VERSION}"; then
      fatal "SwiftDialog ${version} is below the required minimum ${MIN_SWIFTDIALOG_VERSION}"
    fi
  }

# Function: ensure_temp_workspace
# Description: Create a unique temporary directory for JSON and session files.
#              mktemp creates the directory 0700, which SwiftDialog cannot traverse
#              even when launched as root -- it exits 202 on every file inside. The
#              directory must be widened to the standard 755 for the dialog to read
#              its configuration. Nothing secret is written here.
  ensure_temp_workspace() {
    TEMP_DIR=$(mktemp -d "/private/tmp/dialog_starterkit.XXXXXX") || fatal "Unable to create temporary directory"
    SELECTION_JSON_FILE="${TEMP_DIR}/selection.json"
    INSPECT_JSON_FILE="${TEMP_DIR}/inspect.json"
    INSPECT_COMMAND_FILE="${TEMP_DIR}/inspect.command"
    INSPECT_SESSIONS_DIR="${TEMP_DIR}/sessions"

    mkdir -p "${INSPECT_SESSIONS_DIR}" || fatal "Unable to create Inspect Mode sessions directory"
    : > "${INSPECT_COMMAND_FILE}"

    chmod 755 "${TEMP_DIR}" "${INSPECT_SESSIONS_DIR}" || fatal "Unable to set temporary workspace permissions"
    chmod 644 "${INSPECT_COMMAND_FILE}" || fatal "Unable to set command file permissions"

    info "Created temporary workspace: ${TEMP_DIR}"
  }

# Function: ensure_icons_directory
# Description: Create the branding icons directory when missing.
  ensure_icons_directory() {
    if [[ -d "${ICONS_DIR}" ]]; then
      info "Icons directory already exists: ${ICONS_DIR}"
      return 0
    fi
    execute mkdir -p "${ICONS_DIR}" || fatal "Unable to create icons directory: ${ICONS_DIR}"
    execute chmod 755 "${ICONS_DIR}" || true
    execute chown root:wheel "${ICONS_DIR}" || true
    info "Created icons directory: ${ICONS_DIR}"
  }

# --- App catalogue ---

# Function: validate_app_catalogue
# Description: Validate each FriendlyName,Location,Trigger CSV record before use.
  validate_app_catalogue() {
    local app_entry app_name app_location app_trigger

    (( ${#APPS[@]} > 0 )) || fatal "App catalogue is empty"

    for app_entry in "${APPS[@]}"; do
      IFS=',' read -r app_name app_location app_trigger <<< "${app_entry}"
      [[ -n "${app_name}" ]] || fatal "App catalogue entry is missing a display name: ${app_entry}"
      [[ -n "${app_location}" ]] || fatal "App catalogue entry is missing an install path: ${app_entry}"
      [[ -n "${app_trigger}" ]] || fatal "App catalogue entry is missing a Jamf trigger: ${app_entry}"
      [[ "${app_location}" == /* ]] || fatal "App install path must be absolute: ${app_location}"
    done

    info "Validated ${#APPS[@]} app catalogue entries"
  }

# Function: get_app_field
# Description: Return field 1 (name), 2 (path), or 3 (trigger) from a CSV entry.
# Usage: get_app_field "FriendlyName,/path.app,trigger" 1
  get_app_field() {
    local app_entry="${1:-}"
    local field="${2:-}"
    case "${field}" in
      1) printf '%s\n' "${app_entry%%,*}" ;;
      2)
        local remainder="${app_entry#*,}"
        printf '%s\n' "${remainder%,*}"
        ;;
      3) printf '%s\n' "${app_entry##*,}" ;;
      *)
        error "get_app_field requires field 1, 2, or 3"
        return 1
        ;;
    esac
  }

# Function: find_app_entry_by_name
# Description: Return the catalogue CSV entry matching a display name.
# Usage: entry=$(find_app_entry_by_name "iTerm")
# Returns: Prints the CSV entry on success; returns 1 when not found
  find_app_entry_by_name() {
    local wanted_name="${1:-}"
    local app_entry app_name

    [[ -n "${wanted_name}" ]] || return 1

    for app_entry in "${APPS[@]}"; do
      app_name=$(get_app_field "${app_entry}" 1)
      if [[ "${app_name}" == "${wanted_name}" ]]; then
        printf '%s\n' "${app_entry}"
        return 0
      fi
    done
    return 1
  }

# Function: is_valid_image
# Description: Confirm a path holds real image data. Object stores often answer
#              requests for missing objects with a 200 AccessDenied XML body, so a
#              cached .png can contain markup instead of an image.
# Usage: is_valid_image "/Library/Management/Dialog-StarterKit/Branding/Icons/install_iterm.png"
# Returns: 0 when the file is an image, 1 otherwise
  is_valid_image() {
    local candidate="${1:-}"

    [[ -f "${candidate}" ]] || return 1
    [[ "$(file -b --mime-type "${candidate}" 2>/dev/null)" == image/* ]]
  }

# Function: log_unusable_resources
# Description: Report every icon path in a dialog JSON file that SwiftDialog cannot
#              load, so a 201 or 202 exit names the offending resource in the log.
# Usage: log_unusable_resources "${SELECTION_JSON_FILE}"
  log_unusable_resources() {
    local json_file="${1:-}"
    local resource_path

    [[ -f "${json_file}" ]] || return 0

    while IFS= read -r resource_path; do
      [[ -n "${resource_path}" ]] || continue
      if [[ ! -e "${resource_path}" ]]; then
        error "Referenced resource is missing: ${resource_path}"
      elif [[ -f "${resource_path}" ]] && ! is_valid_image "${resource_path}"; then
        error "Referenced resource is not image data: ${resource_path}"
      fi
    done < <(jq -r '.. | objects | .icon? // empty | select(type == "string")' "${json_file}" 2>/dev/null)
  }

# Function: download_app_icon
# Description: Download a cached branding icon for an app trigger with retries.
# Usage: download_app_icon "install_iterm" "iTerm"
# Returns: 0 when the icon exists or is downloaded, 1 on failure
  download_app_icon() {
    local app_trigger="${1:-}"
    local app_name="${2:-}"
    local icon_path="${ICONS_DIR}/${app_trigger}.png"
    local icon_url="${ICON_BASE_URL}/${app_trigger}.png"
    local attempt=1

    [[ -n "${app_trigger}" ]] || return 1

    if is_valid_image "${icon_path}"; then
      info "${app_name} icon already cached"
      return 0
    fi

    if [[ -f "${icon_path}" ]]; then
      warn "Discarding cached ${app_name} icon because it does not contain image data"
      execute rm -f "${icon_path}" || true
    fi

    while (( attempt <= ICON_DOWNLOAD_ATTEMPTS )); do
      info "Downloading ${app_name} icon (attempt ${attempt}/${ICON_DOWNLOAD_ATTEMPTS})"
      if curl -fsSL --connect-timeout 15 --max-time 60 "${icon_url}" -o "${icon_path}" \
        && is_valid_image "${icon_path}"; then
        execute chmod 644 "${icon_path}" || true
        execute chown root:wheel "${icon_path}" || true
        info "Cached icon for ${app_name}"
        return 0
      fi
      warn "Icon download failed for ${app_name}"
      execute rm -f "${icon_path}" || true
      if (( attempt < ICON_DOWNLOAD_ATTEMPTS )); then
        sleep $(( attempt * 2 ))
      fi
      (( attempt++ ))
    done

    warn "Continuing without a cached icon for ${app_name}"
    return 1
  }

# Function: cache_app_icons
# Description: Ensure branding icons are cached for every catalogue entry.
  cache_app_icons() {
    local app_entry app_name app_trigger

    ensure_icons_directory
    for app_entry in "${APPS[@]}"; do
      app_name=$(get_app_field "${app_entry}" 1)
      app_trigger=$(get_app_field "${app_entry}" 3)
      download_app_icon "${app_trigger}" "${app_name}" || true
    done
  }

# Function: get_icon_for_app
# Description: Resolve a usable icon, preferring the cached branding icon and
#              falling back to an installed app bundle. Returns nothing when
#              neither is usable -- SwiftDialog exits 202 if it is handed a path
#              that is missing or not an image, which aborts the whole dialog.
# Usage: icon=$(get_icon_for_app "install_iterm" "/Applications/iTerm.app")
  get_icon_for_app() {
    local app_trigger="${1:-}"
    local app_location="${2:-}"
    local icon_path="${ICONS_DIR}/${app_trigger}.png"

    if is_valid_image "${icon_path}"; then
      printf '%s\n' "${icon_path}"
      return 0
    fi

    if [[ -e "${app_location}" ]]; then
      printf '%s\n' "${app_location}"
      return 0
    fi

    return 0
  }

# --- Selection dialog ---

# Function: build_selection_json
# Description: Write the checkbox selection dialog JSON for the full catalogue.
  build_selection_json() {
    local app_entry app_name app_location app_trigger app_icon
    local checkbox_json

    checkbox_json=$(
      {
        for app_entry in "${APPS[@]}"; do
          app_name=$(get_app_field "${app_entry}" 1)
          app_location=$(get_app_field "${app_entry}" 2)
          app_trigger=$(get_app_field "${app_entry}" 3)
          app_icon=$(get_icon_for_app "${app_trigger}" "${app_location}")
          jq -n \
            --arg label "${app_name}" \
            --arg icon "${app_icon}" \
            '{label: $label, checked: true}
             + (if $icon == "" then {} else {icon: $icon} end)'
        done
      } | jq -s '.'
    ) || fatal "Unable to build checkbox JSON"

    jq -n \
      --arg title "Starter Kit" \
      --arg subtitle "Choose the apps to install" \
      --arg message "Please select the apps you want to install.\n\nScroll down to see them all." \
      --arg icon "${ICON}" \
      --arg support_url "${SUPPORT_URL}" \
      --argjson checkbox "${checkbox_json}" \
      '{
        title: $title,
        subtitle: $subtitle,
        message: $message,
        messagefont: "size=14",
        icon: $icon,
        iconalttext: "Starter Kit",
        button1text: "Install",
        button1symbol: "arrow.down.circle.fill,leading",
        button2text: "Cancel",
        infobuttontext: "Support",
        infobuttonaction: $support_url,
        checkboxstyle: {style: "switch", size: "small"},
        checkbox: $checkbox
      }' > "${SELECTION_JSON_FILE}" || fatal "Unable to write selection JSON"

    chmod 644 "${SELECTION_JSON_FILE}" || fatal "Unable to set selection JSON permissions"

    info "Wrote selection dialog JSON: ${SELECTION_JSON_FILE}"
  }

# Function: show_selection_dialog
# Description: Prompt the user to choose apps and populate SELECTED_APPS.
# Returns: 0 when one or more apps are selected, 1 when the user declines
  show_selection_dialog() {
    local returncode=0
    local selection_json=""
    local app_name selected_value app_entry

    SELECTED_APPS=()
    build_selection_json

    info "Launching selection dialog for ${CURRENT_USER}"
    selection_json=$(
      "${DIALOG_BINARY}" \
        --jsonfile "${SELECTION_JSON_FILE}" \
        --json \
        --height "${SELECTION_DIALOG_HEIGHT}" \
        --timer 300 \
        --hidetimerbar
    ) || returncode=$?

    case "${returncode}" in
      0)
        info "${CURRENT_USER} clicked Install"
        ;;
      2)
        info "${CURRENT_USER} clicked Cancel"
        return 1
        ;;
      3)
        info "${CURRENT_USER} clicked Support"
        return 1
        ;;
      4|20)
        info "${CURRENT_USER} allowed the selection dialog timer to expire"
        return 1
        ;;
      5)
        info "Selection dialog was closed by a quit command"
        return 1
        ;;
      10)
        info "${CURRENT_USER} quit the selection dialog with Command-Q"
        return 1
        ;;
      201|202)
        error "SwiftDialog could not load an icon or file resource referenced by ${SELECTION_JSON_FILE} (code ${returncode})"
        log_unusable_resources "${SELECTION_JSON_FILE}"
        return 1
        ;;
      203)
        error "SwiftDialog rejected a colour value in ${SELECTION_JSON_FILE}"
        return 1
        ;;
      *)
        warn "Unexpected SwiftDialog return code from selection dialog: ${returncode}"
        return 1
        ;;
    esac

    if [[ -z "${selection_json}" ]]; then
      warn "Selection dialog returned empty JSON"
      return 1
    fi

    if ! printf '%s' "${selection_json}" | jq -e 'type == "object"' >/dev/null 2>&1; then
      warn "Selection dialog returned malformed JSON"
      return 1
    fi

    while IFS=$'\t' read -r app_name selected_value; do
      [[ -n "${app_name}" ]] || continue
      if [[ "${selected_value}" == "true" ]]; then
        if app_entry=$(find_app_entry_by_name "${app_name}"); then
          info "${app_name} selected for install"
          SELECTED_APPS+=("${app_entry}")
        else
          warn "Ignoring unknown selected app name: ${app_name}"
        fi
      else
        info "${app_name} will be skipped"
      fi
    done < <(printf '%s' "${selection_json}" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')

    if (( ${#SELECTED_APPS[@]} == 0 )); then
      warn "No apps were selected for install"
      return 1
    fi

    info "Selected ${#SELECTED_APPS[@]} app(s) for install"
    return 0
  }

# --- Inspect Mode progress ---

# Function: build_inspect_json
# Description: Write an Inspect Mode preset 1 config for the selected apps only.
#              Note: preset 1 does not reliably display the top-level message, and
#              it cannot be updated after launch, so the wording must stand for the
#              whole run. Completion is signalled by the window closing itself.
  build_inspect_json() {
    local app_entry app_name app_location app_trigger app_icon
    local items_json
    local gui_index=0

    items_json=$(
      {
        for app_entry in "${SELECTED_APPS[@]}"; do
          app_name=$(get_app_field "${app_entry}" 1)
          app_location=$(get_app_field "${app_entry}" 2)
          app_trigger=$(get_app_field "${app_entry}" 3)
          app_icon=$(get_icon_for_app "${app_trigger}" "${app_location}")
          jq -n \
            --arg id "${app_trigger}" \
            --arg displayName "${app_name}" \
            --argjson guiIndex "${gui_index}" \
            --arg path "${app_location}" \
            --arg icon "${app_icon}" \
            '{
              id: $id,
              displayName: $displayName,
              guiIndex: $guiIndex,
              paths: [$path],
              description: "Jamf trigger: \($id)"
            }
            + (if $icon == "" then {} else {icon: $icon} end)'
          gui_index=$((gui_index + 1))
        done
      } | jq -s '.'
    ) || fatal "Unable to build Inspect Mode items JSON"

    jq -n \
      --arg title "Installing Apps" \
      --arg message "Installing your selected apps. This window closes automatically when everything is done." \
      --arg icon "${ICON}" \
      --arg iconBasePath "${ICONS_DIR}" \
      --argjson items "${items_json}" \
      '{
        preset: "1",
        title: $title,
        message: $message,
        icon: $icon,
        iconBasePath: $iconBasePath,
        size: "standard",
        scanInterval: 2,
        cachePaths: [
          "/Library/Application Support/JAMF/Downloads",
          "/Library/Application Support/JAMF/Waiting Room"
        ],
        cacheExtensions: ["download", "pkg", "dmg"],
        button1text: "Please wait",
        button1disabled: true,
        button2visible: false,
        autoEnableButton: true,
        autoEnableButtonText: "Done",
        items: $items
      }' > "${INSPECT_JSON_FILE}" || fatal "Unable to write Inspect Mode JSON"

    chmod 644 "${INSPECT_JSON_FILE}" || fatal "Unable to set Inspect Mode JSON permissions"

    info "Wrote Inspect Mode JSON for ${#SELECTED_APPS[@]} selected app(s)"
  }

# Function: inspect_command
# Description: Append a command to the Inspect Mode command file when present.
#              Inspect Mode uses its own trigger-file IPC and ignores the standard
#              command-file verbs, so this is a best-effort graceful shutdown only.
#              Callers must still terminate the process themselves.
# Usage: inspect_command "quit:"
  inspect_command() {
    local command_text="${1:-}"
    [[ -n "${command_text}" ]] || return 0
    [[ -n "${INSPECT_COMMAND_FILE:-}" && -f "${INSPECT_COMMAND_FILE}" ]] || return 0
    printf '%s\n' "${command_text}" >> "${INSPECT_COMMAND_FILE}"
  }

# Function: launch_inspect_dialog
# Description: Start Inspect Mode in the background and record its process ID.
  launch_inspect_dialog() {
    build_inspect_json

    info "Launching Inspect Mode install progress dialog"
    DIALOG_COMMAND_FILE="${INSPECT_COMMAND_FILE}" \
      "${DIALOG_BINARY}" \
        --inspect-mode \
        --inspect-config "${INSPECT_JSON_FILE}" \
        --published-sessions-dir "${INSPECT_SESSIONS_DIR}" \
        --commandfile "${INSPECT_COMMAND_FILE}" \
        &
    INSPECT_PID=$!

    sleep "${INSPECT_READY_WAIT_SECONDS}"

    if ! kill -0 "${INSPECT_PID}" 2>/dev/null; then
      INSPECT_PID=""
      fatal "Inspect Mode dialog exited unexpectedly during startup"
    fi

    info "Inspect Mode dialog is running as PID ${INSPECT_PID}"
  }

# Function: wait_for_inspect_dialog
# Description: Wait for the user to dismiss the Inspect Mode dialog, closing it
#              automatically once the timeout is reached. Reaching the timeout is
#              the expected outcome, not a fault.
# Usage: wait_for_inspect_dialog 60
  wait_for_inspect_dialog() {
    local timeout_seconds="${1:-${INSPECT_AUTO_CLOSE_SECONDS}}"
    local elapsed=0

    [[ -n "${INSPECT_PID:-}" ]] || return 0

    while kill -0 "${INSPECT_PID}" 2>/dev/null; do
      if (( elapsed >= timeout_seconds )); then
        info "Closing the install progress dialog after ${timeout_seconds}s"
        inspect_command "quit:"
        sleep 1
        kill "${INSPECT_PID}" 2>/dev/null || true
        wait "${INSPECT_PID}" 2>/dev/null || true
        INSPECT_PID=""
        return 0
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done

    wait "${INSPECT_PID}" 2>/dev/null || true
    INSPECT_PID=""
    info "Inspect Mode dialog closed"
  }

# Function: show_failure_summary_dialog
# Description: Show a final regular dialog summarising apps that failed to install.
  show_failure_summary_dialog() {
    local failed_list
    local returncode=0

    failed_list=$(printf -- '- %s\n' "${FAILED_APPS[@]}")

    info "Showing install failure summary dialog"
    "${DIALOG_BINARY}" \
      --title "Starter Kit Install Incomplete" \
      --subtitle "Some apps could not be installed" \
      --message "The following apps did not install successfully:\n\n${failed_list}\n\nTry again from Self Service, or contact Support if the problem continues." \
      --icon "${ICON}" \
      --iconalttext "Starter Kit" \
      --button1text "Close" \
      --infobuttontext "Support" \
      --infobuttonaction "${SUPPORT_URL}" \
      --timer 300 \
      --hidetimerbar \
      || returncode=$?

    case "${returncode}" in
      0) info "${CURRENT_USER} dismissed the failure summary" ;;
      3) info "${CURRENT_USER} clicked Support from the failure summary" ;;
      4|20) info "${CURRENT_USER} allowed the failure summary timer to expire" ;;
      10) info "${CURRENT_USER} quit the failure summary with Command-Q" ;;
      *) warn "Unexpected SwiftDialog return code from failure summary: ${returncode}" ;;
    esac
  }

# Function: install_selected_apps
# Description: Install each selected app via Jamf, verifying the install path with retries.
  install_selected_apps() {
    local app_entry app_name app_location app_trigger
    local attempt installed="false"

    FAILED_APPS=()

    for app_entry in "${SELECTED_APPS[@]}"; do
      app_name=$(get_app_field "${app_entry}" 1)
      app_location=$(get_app_field "${app_entry}" 2)
      app_trigger=$(get_app_field "${app_entry}" 3)
      installed="false"

      if [[ -e "${app_location}" ]]; then
        info "${app_name} is already installed at ${app_location}"
        continue
      fi

      info "Installing ${app_name} via Jamf trigger ${app_trigger}"
      attempt=1
      while (( attempt <= MAX_INSTALL_RETRIES )); do
        if [[ "${TESTING_MODE}" == "true" ]]; then
          info "[TESTING MODE] Would run: ${JAMF_BINARY} policy -event ${app_trigger}"
          installed="true"
          break
        fi

        if ! "${JAMF_BINARY}" policy -event "${app_trigger}"; then
          warn "Jamf policy for ${app_name} returned non-zero on attempt ${attempt}/${MAX_INSTALL_RETRIES}"
        fi

        sleep 2

        if [[ -e "${app_location}" ]]; then
          info "${app_name} installed successfully"
          installed="true"
          break
        fi

        warn "${app_name} not found at ${app_location} after attempt ${attempt}/${MAX_INSTALL_RETRIES}"
        (( attempt++ ))
      done

      if [[ "${installed}" != "true" ]]; then
        warn "${app_name} failed to install after ${MAX_INSTALL_RETRIES} attempts"
        FAILED_APPS+=("${app_name}")
      fi
    done
  }

# Function: finalise_install_progress
# Description: Close Inspect Mode appropriately and report the overall install result.
# Returns: 0 when every selected app is present, 1 when any install failed
  finalise_install_progress() {
    if (( ${#FAILED_APPS[@]} == 0 )); then
      info "All selected apps are installed"
      wait_for_inspect_dialog "${INSPECT_AUTO_CLOSE_SECONDS}"
      return 0
    fi

    info "Closing Inspect Mode before showing the failure summary"
    inspect_command "quit:"
    sleep 1
    if [[ -n "${INSPECT_PID:-}" ]] && kill -0 "${INSPECT_PID}" 2>/dev/null; then
      kill "${INSPECT_PID}" 2>/dev/null || true
      wait "${INSPECT_PID}" 2>/dev/null || true
    fi
    INSPECT_PID=""

    show_failure_summary_dialog
    error "Failed to install: ${FAILED_APPS[*]}"
    return 1
  }

##########################################################################################
# Main Script
##########################################################################################

  require_macos_version
  require_jamf_binary
  require_logged_in_user

  if is_meeting_active; then
    warn "Zoom or Teams appears to be active. Skipping starter kit prompt for this run."
    exit 0
  fi
  info "No active meeting detected. Proceeding."

  ensure_swiftdialog
  require_dialog_icon
  ensure_temp_workspace
  validate_app_catalogue
  cache_app_icons

  if ! show_selection_dialog; then
    info "No apps will be installed this run."
    exit 0
  fi

  launch_inspect_dialog
  install_selected_apps
  finalise_install_progress || exit $?
