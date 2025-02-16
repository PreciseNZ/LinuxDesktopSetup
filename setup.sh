#!/bin/bash

# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)" | tee -a setup.log
    exit 1
fi

# === FUNCTION DEFINITIONS ===
# Ensure progress tracking file exists
if [ ! -f setup-progress.json ]; then
    echo '{}' > setup-progress.json
fi

# Function to mark a step as completed
mark_step_complete() {
    step_name="$1"
    jq --arg step "$step_name" '.[$step] = "success"' setup-progress.json > temp.json && mv temp.json setup-progress.json
}

# Function to mark a step as failed
mark_step_failed() {
    step_name="$1"
    jq --arg step "$step_name" '.[$step] = "failed"' setup-progress.json > temp.json && mv temp.json setup-progress.json
}

# Function to check if a step was already completed
is_step_completed() {
    step_name="$1"
    result=$(jq -r --arg step "$step_name" '.[$step] // empty' setup-progress.json)
    [ "$result" == "success" ]
}

# Function to log and run commands safely
log_and_run() {
    step_name="$1"
    command="$2"

    # Skip step if already completed
    if is_step_completed "$step_name"; then
        echo "[SKIPPING] $step_name - Already completed" | tee -a setup.log
        return 0
    fi

    echo "[RUNNING] $step_name: $command" | tee -a setup.log
    eval "$command" >> setup.log 2>&1
    if [ $? -ne 0 ]; then
        echo "[ERROR] $step_name failed" | tee -a setup.log
        mark_step_failed "$step_name"
        exit 1
    fi

    mark_step_complete "$step_name"
}

# === EXECUTION STARTS HERE ===
echo "Starting Ubuntu setup..." | tee -a setup.log

log_and_run "update_system" "sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove && sudo apt clean"

log_and_run "firmware_update" "sudo fwupdmgr get-updates && sudo fwupdmgr update"

log_and_run "install_nala" "sudo apt install nala -y"
log_and_run "update_nala" "sudo nala update && sudo nala upgrade"

log_and_run "install_terminator_fonts" "sudo nala install terminator fonts-powerline -y"
log_and_run "install_dev_tools" "sudo nala install build-essential git cmake libhidapi-dev -y"
log_and_run "install_certificates" "sudo nala install dirmngr ca-certificates software-properties-common apt-transport-https curl lsb-release -y"
log_and_run "install_python3" "sudo nala install python3 -y"
log_and_run "install_python3_dotenv" "sudo nala install python3-dotenv -y"

log_and_run "disable_network_wait" "sudo systemctl disable NetworkManager-wait-online.service"

echo "Setup complete!" | tee -a setup.log
