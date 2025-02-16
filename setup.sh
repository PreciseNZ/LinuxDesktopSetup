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
    acceptable_exit_codes="${3:-0}"  # Default acceptable exit code is 0

    # Skip step if already completed
    if [ "$step_name" != "update_check" ] && is_step_completed "$step_name"; then
        echo "[SKIPPING] $step_name - Already completed" | tee -a setup.log
        return 0
    fi

    echo "[RUNNING] $step_name: $command" | tee -a setup.log
    eval "$command" >> setup.log 2>&1
    exit_code=$?

    if [[ " $acceptable_exit_codes " =~ " $exit_code " ]]; then
        echo "[SUCCESS] $step_name completed with exit code $exit_code" | tee -a setup.log
        mark_step_complete "$step_name"
    else
        echo "[ERROR] $step_name failed with exit code $exit_code" | tee -a setup.log
        mark_step_failed "$step_name"
        exit 1
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

packages=(
    "terminator fonts-powerline"
    "build-essential git cmake libhidapi-dev"
    "dirmngr ca-certificates software-properties-common apt-transport-https curl lsb-release"
    "python3 python3-dotenv"
    "solaar"
    "rider pycharm-professional"
    "mythes-en-au"
)

# === EXECUTION STARTS HERE ===
echo "Starting Ubuntu setup..." | tee -a setup.log
echo "Core Updates" | tee -a setup.log
log_and_run "initial_system_update" "sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove && sudo apt clean"
log_and_run "firmware_update" "sudo fwupdmgr get-updates && sudo fwupdmgr update" "0 2"
log_and_run "disable_network_wait" "sudo systemctl disable NetworkManager-wait-online.service"

echo "Adding 3rd party keys and repos" | tee -a setup.log
log_and_run "add_jetbrains_gpg_key" \
    "curl -s https://s3.eu-central-1.amazonaws.com/jetbrains-ppa/0xA6E8698A.pub.asc | gpg --dearmor | sudo tee /usr/share/keyrings/jetbrains-ppa-archive-keyring.gpg > /dev/null"
log_and_run "add_jetbrains_repo" \
    "echo 'deb [signed-by=/usr/share/keyrings/jetbrains-ppa-archive-keyring.gpg] http://jetbrains-ppa.s3-website.eu-central-1.amazonaws.com any main' | sudo tee /etc/apt/sources.list.d/jetbrains-ppa.list > /dev/null"
do_update

echo "Installing applications" | tee -a setup.log
for pkg in "${packages[@]}"; do
    install_package "$pkg"
done

do_update
echo "Setup complete!" | tee -a setup.log
