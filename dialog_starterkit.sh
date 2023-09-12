#!/bin/bash
# set -x

#########################################################################################
# Script Information
#########################################################################################
#
# Authors: Martin Piron
#
# Name:     dialog_starterkit.sh
# Version:  1.0.0 (11-09-2023)
# Repo:     https://github.com/ooftee/dialog-starterkit
#
# This script was inspired by Adam Codega's: https://github.com/acodega/dialog-scripts/

#########################################################################################
# General Information
#########################################################################################
#
# Dialog Starter kits
# Install list of apps using siwftDialog and custom jamf triggers.
# Lets users select which apps they want installed or not.

#########################################################################################
# CUSTOM VARIABLES TO EDIT
#########################################################################################

# Apps to install (format is FriendlyName,Location,JamfTrigger&IconName)
APPS=(
  "GitHub Desktop,/Applications/GitHub Desktop.app,install_githubdesktop"
  "Icons,/Applications/Icons.app,install_icons"
  "Imazing Profile Editor,/Applications/iMazing Profile Editor.app,install_imazingprofileeditor"
  "iTerm,/Applications/iTerm.app,install_iterm"
  "Keka,/Applications/Keka.app,install_keka"
)

# Your Icon Public Bucket
BUCKET="https://s3.ap-southeast-2.amazonaws.com/***"

# swiftDialog message (Update icon with path to your company logo)
START_JSON='{
  "title" : "Starter Kit",
  "message" : "Please select the apps you want to install.\n\nScoll down to see them all.",
  "messagefont" : "colour=#666666,weight=medium",
  "icon" : "PATH_TO_LOGO",
  "button1text" : "OK",
  "button2text" : "Cancel",
  "checkboxstyle": {
    "style": "switch",
    "size": "small"
  }
}'

INSTALL_JSON='{
  "title" : "Installing Apps",
  "message" : "Please wait while we install apps:",
  "messagefont" : "colour=#666666,weight=medium",
  "icon" : "PATH_TO_LOGO",
  "overlayicon" : "SF=arrow.down.circle.fill,palette=white,black,none,bgcolor=none",
  "position" : "bottomright",
  "button1text" : "Please wait"
}'

#########################################################################################
# SCRIPT VARIABLES
#########################################################################################

# location of dialog and dialog command file
DIALOG_APP="/usr/local/bin/dialog"
DIALOG_COMMAND_FILE="/var/tmp/dialog.log"
START_JSON_FILE="/var/tmp/dialog_START_JSON.json"
INSTALL_JSON_FILE="/var/tmp/dialog_INSTALL_JSON.json"
CHECKED_JSON_FILE="/var/tmp/dialog_CHECKED_JSON.json"

# set progress total to the number of apps in the list
PROGRESS_TOTAL=${#APPS[@]}

# Jamf binary
JAMF="/usr/local/bin/jamf"

#########################################################################################
# Testing and Logging
#########################################################################################
# Testing flag will enable the script logic to run without dependencies
#TESTING_MODE="false" # false (default) or true to speed things up and write more logs

# Enable logging to a file on disk and specify a directory
ENABLE_LOGFILE="true" # false (default) or true to write the logs to a file
LOGDIR="/Library/Management/Dialog-SK/Logs" # /var/tmp (default) or override by specifying a path

#########################################################################################
# Global Functions
#########################################################################################
# Logging:  info, warn, error, fatal (exits 1 or pass in an exit code after msg)
# Init:     sets up logging and welcome text
# Cleanup:  trap function to clean up and print finish text (modify as required)

echoerr() { printf "%s\n" "$*" >&2 ; }
echolog() { if [[ "${ENABLE_LOGFILE}" == "true" ]]; then printf "%s %s\n" "$(date +"%F %R:%S")" "$*" >>"${LOGFILE}"; fi }
info()    { echoerr "[INFO ] $*" ; echolog "[INFO ]  $*" ; }
warn()    { echoerr "[WARN ] $*" ; echolog "[WARN ]  $*" ; }
error()   { echoerr "[ERROR] $*" ; echolog "[ERROR]  $*" ; }
fatal()   { echoerr "[FATAL] $*" ; echolog "[FATAL]  $*" ; exit "${2:-1}" ; }

SCRIPT_NAME=$(basename "${0}") # Not inline in case ZHS
_init () {
  # Setup log file if enabled
  if [[ "${ENABLE_LOGFILE}" == "true" ]]; then
    LOGFILE="${LOGDIR:-/var/tmp}/$(date +"%F_%H.%M.%S")-${SCRIPT_NAME}.log"
    [[ -n ${LOGDIR} && ! -d ${LOGDIR} ]] && mkdir -p "${LOGDIR}"
    [[ ! -f ${LOGFILE} ]] && touch "${LOGFILE}"
  fi
  
  info "## Script: ${SCRIPT_NAME}"
  info "## Start : $(date +"%F %R:%S")"
}

cleanup() {
  EXIT_CODE=$?
  # Create this function to perform clean up at exit
  # exit_cleanup "${EXIT_CODE}" # not used
  info "## Finish: $(date +"%F %R:%S")"
  info "## Exit Code: ${EXIT_CODE}"
}

# Global Function Setup
trap cleanup EXIT
_init

#########################################################################################
# Script Functions
#########################################################################################

dialog_command() {
  echo "$1"
  echo "$1"  >> "${DIALOG_COMMAND_FILE}"
}

finalise(){
  dialog_command "overlayicon: SF=checkmark.circle.fill,palette=white,black,none,bgcolor=none"
  dialog_command "progress: complete"
  dialog_command "button1text: Done"
  dialog_command "button1: enable" 
}

#########################################################################################
# Main Script
#########################################################################################

# Install swiftDialog if not installed
if [[ ! -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
  warn "swiftDialog missing, installing"
  "${JAMF}" policy -event install_swiftdialog
else
  info "swiftDialog already installed"
fi

# Install jq if not installed
if [[ ! -e "/usr/local/bin/jq" ]]; then
  warn "JQ missing, installing"
  "${JAMF}" policy -event install_jq
else
  info "JQ already installed"
fi

# Create icons folder and download them
if [[ ! -e "/Library/Management/Dialog-SK/Branding/Icons/" ]]; then
  info "Creating Icons folder"
  mkdir -p "/Library/Management/Dialog-SK/Branding/Icons/"
else
  info "Icons folder already exists"
fi

for APP in "${APPS[@]}"; do
  APP_NAME=$(echo "$APP" | cut -d ',' -f1)
  APP_TRIGGER=$(echo "$APP" | cut -d ',' -f3)
  if [[ ! -e "/Library/Management/Dialog-SK/Branding/Icons/${APP_TRIGGER}.png" ]]; then
    warn "${APP_NAME} icon not found, downloading"
    curl "${BUCKET}${APP_TRIGGER}.png" -o "/Library/Management/Dialog-SK/Branding/Icons/${APP_TRIGGER}.png"
  elif [[ -e "/Library/Management/Dialog-SK/Branding/Icons/${APP_TRIGGER}.png" ]]; then
    info "${APP_NAME} icon already cached"
  fi
done

# Create the list of apps and format it in json
CHECKBOX_JSON=$(printf '%s\n' "${APPS[@]}" | awk -F ',' '{printf "{\"label\":\"%s\",\"checked\":true,\"icon\":\"/Library/Management/Dialog-SK/Branding/Icons/%s.png\"}\n", $1, $3}' | jq -s '{"checkbox": .}')

LISTITEMS_JSON=$(printf '%s\n' "${APPS[@]}" | awk -F ',' '{printf "{\"title\":\"%s\",\"icon\":\"/Library/Management/Dialog-SK/Branding/Icons/%s.png\",\"status\":\"pending\",\"statustext\":\"Pending\"}\n", $1, $3}' | jq -s '{"listitem": .}')

# Merge json variables into one file
START_MERGED_JSON=$(jq -n --argjson START_JSON "${START_JSON}" --argjson CHECKBOX_JSON "${CHECKBOX_JSON}" '$START_JSON + $CHECKBOX_JSON')
echo "${START_MERGED_JSON}" > "${START_JSON_FILE}"

INSTALL_MERGED_JSON=$(jq -n --argjson INSTALL_JSON "${INSTALL_JSON}" --argjson LISTITEMS_JSON "${LISTITEMS_JSON}" '$INSTALL_JSON + $LISTITEMS_JSON') 
echo "${INSTALL_MERGED_JSON}" > "${INSTALL_JSON_FILE}"

# Launch Dialog and display the lsit of apps available to install
DIALOG_CMD="${DIALOG_APP} 
--jsonfile ${START_JSON_FILE} \
--json"

info "Launching Dialog - App Select"
APPS_SELECTED=$($DIALOG_CMD)

# Exit if user clicked cancel (array is empty)
if [[ ! ${APPS_SELECTED[@]} ]]; then
 fatal "User clicked cancel."
fi

# Read the JSON object and construct an array of key-value pairs
APPS_SELECTED_values=()
while IFS= read -r line; do
  APPS_SELECTED_values+=("$line")
done < <(echo "${APPS_SELECTED}" | jq -r 'to_entries | map("\(.key)=\(.value)")[]')

# Create array with all the apps to install
INSTALL_IS_TRUE=()
for APP in "${APPS_SELECTED_values[@]}"; do
  APP_NAME=$(echo "${APP}" | cut -d '=' -f1)
  VALUE=$(echo "${APP}" | cut -d '=' -f2)
  if [[ "${VALUE}" == "true" ]]; then
    info "${APP_NAME} will be installed"
    INSTALL_IS_TRUE+=("${APP_NAME}")
  elif [[ "${VALUE}" == "false" ]]; then
    info "${APP_NAME} will be skipped"
    # Update the status and statustext of skipped apps in the JSON file
    /usr/local/bin/jq --arg app "${APP_NAME}" '.listitem |= map(if .title == $app then .status = "fail" | .statustext = "Skipping" else . end)' "${INSTALL_JSON_FILE}" > "${CHECKED_JSON_FILE}"
    # Rename the updated file back to the original one
    mv "${CHECKED_JSON_FILE}" "${INSTALL_JSON_FILE}"
  fi
done

# Update Dialog with the install json file
DIALOG_CMD="${DIALOG_APP} \
--progress ${PROGRESS_TOTAL} \
--button1disabled \
--jsonfile $INSTALL_JSON_FILE"

STEP_PROGRESS=0

info "Launching Dialog - App Install"
eval "$DIALOG_CMD" & sleep 2
 
# Loop thru array and install apps if they were selected
for APP in "${APPS[@]}"; do
  APP_NAME=$(echo "${APP}" | cut -d ',' -f1)
  APP_TRIGGER=$(echo "${APP}" | cut -d ',' -f3)
  APP_LOCATION=$(echo "${APP}" | cut -d ',' -f2)
  STEP_PROGRESS=$(( 1 + STEP_PROGRESS ))
  dialog_command "progress: ${STEP_PROGRESS}"
  STATUS=$(jq --arg app "${APP_NAME}" '.listitem[] | select(.title == $app) | .statustext' "${INSTALL_JSON_FILE}" | tr -d '"')
  if [[ "${STATUS}" = "Pending" ]]; then
    if [[ ! -e "${APP_LOCATION}" ]]; then
      info "${APP_NAME} not installed, installing"
      dialog_command "listitem: ${APP_NAME}: wait"
      dialog_command "progresstext: Installing ${APP_NAME}"
      "${JAMF}" policy -event "${APP_TRIGGER}"
      sleep 1
      if [[ -e "${APP_LOCATION}" ]]; then
        info "${APP_NAME} installed"
        dialog_command "listitem: ${APP_NAME}: success"
      else
        error "${APP_NAME} Failed"
        dialog_command "listitem: ${APP_NAME}: error"
        FAILED_STATUS+=("${APP_TRIGGER}")
      fi
    elif [[ -e "${APP_LOCATION}" ]]; then
      info "${APP_NAME} installed"
      dialog_command "progresstext: ${APP_NAME} is already installed"
      dialog_command "listitem: ${APP_NAME}: success"
    else
      error "${APP_NAME} Failed"
      dialog_command "listitem: ${APP_NAME}: error"
      FAILED_STATUS+=("${APP_TRIGGER}")
    fi
  elif [[ "${STATUS}" = "Skipping" ]]; then
    warn "${APP_NAME} was NOT selected by the user to be installed."
    dialog_command "progresstext: Skipping ${APP_NAME}"
  fi
  sleep 1
done

# Loop through failed array and report back if required
if [[ ${#FAILED_STATUS[@]} -eq 0 ]] ; then
  info "All apps installed."
  dialog_command "progresstext: All done!"
else
  error "Failed: ${FAILED_STATUS[*]}"
  dialog_command "progresstext: Some installations have failed..."
fi

# Finishing up
finalise