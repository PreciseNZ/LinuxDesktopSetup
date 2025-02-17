#!/bin/bash

# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)" | tee -a setup.log
    exit 1
fi

required_cmds=("jq" "nala" "add-apt-repository" "curl" "gpg")
missing_cmds=()

for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        missing_cmds+=("$cmd")
    fi
done

if [ ${#missing_cmds[@]} -gt 0 ]; then
    echo "[ERROR] Missing required commands: ${missing_cmds[*]}" | tee -a setup.log
    echo "Please install them first and rerun the script."
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
    local step_name="$1"
    local command="$2"
    local acceptable_exit_codes="${3:-0}"  # Default exit code is 0

    # Skip step if already completed
    if [[ "$step_name" != "update_check" ]] && is_step_completed "$step_name"; then
        echo "[SKIPPING] $step_name - Already completed" | tee -a setup.log
        return 0
    fi

    echo "[RUNNING] $step_name: $command" | tee -a setup.log
    if eval "$command" >> setup.log 2>&1; then
        echo "[SUCCESS] $step_name completed successfully" | tee -a setup.log
        mark_step_complete "$step_name"
    else
        exit_code=$?
        if [[ " $acceptable_exit_codes " =~ " $exit_code " ]]; then
            echo "[SUCCESS] $step_name completed with acceptable exit code $exit_code" | tee -a setup.log
            mark_step_complete "$step_name"
        else
            echo "[ERROR] $step_name failed with exit code $exit_code" | tee -a setup.log
            mark_step_failed "$step_name"
            exit 1
        fi
    fi
}


do_update() {
    log_and_run "update_check" "sudo nala update && sudo nala upgrade"
}

install_package() {
    package="$1"
    # Create a unique step name by replacing spaces with underscores
    step_name="install_$(echo "$package" | tr ' ' '_')"
    log_and_run "$step_name" "sudo nala install $package -y"
}

add_repository() {
    name="$1"
    key_url="$2"
    key_path="$3"
    repo_string="$4"
    repo_file="$5"

    log_and_run "add_${name}_gpg_key" "curl -s $key_url | gpg --dearmor | sudo tee $key_path > /dev/null"
    log_and_run "add_${name}_repo" "echo '$repo_string' | sudo tee $repo_file > /dev/null"
}

# === Load Package List from External JSON ===
packages_file="packages.json"
if [ ! -f "$packages_file" ]; then
    echo "[ERROR] $packages_file not found" | tee -a setup.log
    exit 1
fi

# === EXECUTION STARTS HERE ===
echo "Starting Ubuntu setup..." | tee -a setup.log

echo "Core Updates" | tee -a setup.log
log_and_run "initial_system_update" "sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove && sudo apt clean"
log_and_run "firmware_update" "sudo fwupdmgr get-updates && sudo fwupdmgr update" "0 2"
log_and_run "disable_network_wait" "sudo systemctl disable NetworkManager-wait-online.service"

echo "Adding 3rd party keys and repos" | tee -a setup.log
jq -c '.repositories[]' packages.json | while read -r repo; do
    add_repository \
        "$(echo "$repo" | jq -r '.name')" \
        "$(echo "$repo" | jq -r '.key_url')" \
        "$(echo "$repo" | jq -r '.key_path')" \
        "$(echo "$repo" | jq -r '.repo')" \
        "$(echo "$repo" | jq -r '.repo_file')"
done


echo "Adding PPAs" | tee -a setup.log
jq -r '.ppas[]' packages.json | while read -r ppa; do
    log_and_run "add_ppa_${ppa//:/_}" "sudo add-apt-repository -y $ppa"
done

do_update

echo "Installing applications" | tee -a setup.log
mapfile -t packages < <(jq -r '.packages[]' "$packages_file")
for pkg in "${packages[@]}"; do
    install_package "$pkg"
done

do_update
echo "Setup complete!" | tee -a setup.log

