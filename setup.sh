#!/bin/bash

# Gather current user details
CURRENT_USER=$(logname)
USER_HOME=$(eval echo ~$CURRENT_USER)

# Setup the Candy
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'  # Reset color
VERBOSE=false
REINIT=false

show_header() {
    local header="$1"
    echo -e "\n${WHITE}=========================================${RESET}"
    echo -e "${CYAN}  $header ${RESET}"
    echo -e "${WHITE}=========================================${RESET}"
    echo "$header" >> setup.log
}

show_error() {
    local header="$1"
    echo -e "\n${RED}=========================================${RESET}"
    echo -e "${RED}  $header ${RESET}"
    echo -e "${RED}=========================================${RESET}\n"
    echo "$header" >> setup.log
}

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    while ps -p $pid &>/dev/null; do
        local temp=${spinstr#?}
        printf "%c" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b"
    done
    printf " \b"
}

#
# Pre-flight checks
#
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}🔹 Elevating privileges... You may be prompted for your password.${RESET}"
    exec sudo bash "$0" "$@"  # Restart the script with sudo
    exit 0
fi

echo "$(date '+%Y-%m-%d %H:%M:%S')" > setup.log

for arg in "$@"; do
    if [[ "$arg" == "--verbose" ]]||[[ "$arg" == "-v" ]]; then
        VERBOSE=true
    fi
    if [[ "$arg" == "--reinit" ]]||[[ "$arg" == "-r" ]]; then
        REINIT=true
    fi
done


required_cmds=("jq" "nala" "add-apt-repository" "curl" "gpg")
missing_cmds=()

for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        missing_cmds+=("$cmd")
    fi
done

if [ ${#missing_cmds[@]} -gt 0 ]; then
    show_error "[ERROR] Missing required commands: ${missing_cmds[*]}"
    echo "Please install them first and rerun the script."
    exit 1
fi

if [ $REINIT = true ] || [ ! -f setup-progress.json ]; then
	show_error "[REINIT] Creating new setup-progress.json file."
    echo '{}' > setup-progress.json
fi

#
# General Functions
#
mark_step_complete() {
    step_name="$1"
    jq --arg step "$step_name" '.[$step] = "success"' setup-progress.json > temp.json && mv temp.json setup-progress.json
}

mark_step_failed() {
    step_name="$1"
    jq --arg step "$step_name" '.[$step] = "failed"' setup-progress.json > temp.json && mv temp.json setup-progress.json
}

is_step_completed() {
    step_name="$1"
    result=$(jq -r --arg step "$step_name" '.[$step] // empty' setup-progress.json)
    [ "$result" == "success" ]
}

log_and_run() {
    local step_name="$1"
    local command="$2"
    local acceptable_exit_codes="${3:-0}"

    if [[ "$step_name" != "update_check" ]] && is_step_completed "$step_name"; then
        echo -e "${YELLOW}[SKIPPING]${RESET} $step_name - Already completed"
        echo -e "Skipping $step_name - Already completed." >> setup.log
        return 0
    fi

    echo -e "${CYAN}[RUNNING]${RESET} $step_name"
    if [ "$VERBOSE" = true ]; then
        echo -e "${WHITE}Command: $command${RESET}"  # Only show the command in verbose mode
    fi
    echo -e "Running $step_name. $command" >> setup.log

    eval "$command" >> setup.log 2>&1 &  # Always log, but not necessarily show
    local pid=$!
    show_spinner $pid  # Show spinner while the command runs
    wait $pid
    local exit_code=$?

    if [[ " $acceptable_exit_codes " =~ " $exit_code " ]]; then
        echo -e "${GREEN}[SUCCESS]${RESET} $step_name completed"
        echo -e "Complete $step_name." >> setup.log
        mark_step_complete "$step_name"
    else
        show_error "$step_name failed with exit code $exit_code"
        mark_step_failed "$step_name"
        exit 1
    fi
}

do_update() {
	echo -e "${WHITE}[UPDATE]${RESET} Conducting update check."
    echo -e "Checking updates." >> setup.log
	eval "nala update" >> setup.log 2>&1 &
	local pid=$!
    show_spinner $pid  # Show spinner while the command runs
    wait $pid
	if apt list --upgradable 2>/dev/null | grep -q 'upgradable'; then
    	log_and_run "update_check" "nala upgrade"
    fi
}

install_nala_package() {
    package="$1"
    step_name="install_$(echo "$package" | tr ' ' '_')"
    log_and_run "$step_name" "nala install $package -y"
}

install_snap_package() {
    package="$1"
    step_name="install_$(echo "$package" | tr ' ' '_')"
    log_and_run "$step_name" "snap install $package -y" "0 64" # 0==Success, 64==Already installed.
}

add_repository() {
    name="$1"
    key_url="$2"
    key_path="$3"
    repo_string="$4"
    repo_file="$5"

    log_and_run "add_${name}_gpg_key" "curl -s $key_url | gpg --dearmor | tee $key_path > /dev/null"
    log_and_run "add_${name}_repo" "echo '$repo_string' | tee $repo_file > /dev/null"
}

packages_file="packages.json"
if [ ! -f "$packages_file" ]; then
    show_error "$packages_file not found!!"
    exit 1
fi

#
# Actual Execution Script
#
show_header "Starting Ubuntu setup. \n   Use: \n    --verbose for more details.\n    --reset to reset progress.\n   Logs stored in setup.log."
show_header "Core Updates"
log_and_run "initial_system_update" "apt update && apt -y dist-upgrade && apt -y autoremove && apt clean"
log_and_run "firmware_update" "fwupdmgr get-updates && fwupdmgr update" "0 2"
log_and_run "disable_network_wait" "systemctl disable NetworkManager-wait-online.service"

show_header "Adding 3rd party keys and repos"
jq -c '.repositories[]' packages.json | while read -r repo; do
    add_repository \
        "$(echo "$repo" | jq -r '.name')" \
        "$(echo "$repo" | jq -r '.key_url')" \
        "$(echo "$repo" | jq -r '.key_path')" \
        "$(echo "$repo" | jq -r '.repo')" \
        "$(echo "$repo" | jq -r '.repo_file')"
done

show_header "Adding PPAs"
jq -r '.ppas[]' packages.json | while read -r ppa; do
    log_and_run "add_ppa_${ppa//:/_}" "add-apt-repository -y $ppa"
done

do_update

show_header "Installing Nala applications"
mapfile -t nalapackages < <(jq -r '.nalapackages[]' "$packages_file")
for pkg in "${nalapackages[@]}"; do
    install_nala_package "$pkg"
done

show_header "Installing Snap applications"
mapfile -t snappackages < <(jq -r '.snappackages[]' "$packages_file")
for pkg in "${snappackages[@]}"; do
    install_snap_package "$pkg"
done

do_update

#
# Configurations and other items
# These are done as the user, not sudo.
#

show_header "Downloading Meslo Nerd Fonts"
log_and_run "download_meslo" "sudo -u $CURRENT_USER wget -P $USER_HOME/.local/share/fonts https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Meslo.zip"
log_and_run "unzip fonts" "sudo -u $CURRENT_USER bash -c 'cd $USER_HOME/.local/share/fonts && unzip -u Meslo.zip && rm Meslo.zip && rm *.txt && rm *.md'"
log_and_run "refresh_font_cache" "sudo -u $CURRENT_USER fc-cache -f"


show_header "Configuring Terminator"
config_file="$USER_HOME/.config/terminator/config"

log_and_run "create_terminator_config" "mkdir -p '$(dirname $config_file)' && touch $config_file"

awk '
BEGIN { inside_profiles=0; inside_default=0; found_cursor=0; found_font=0; found_system_font=0 }
/^\[profiles\]/ { inside_profiles=1; print; next }
/^\s*\[\[/ { inside_default=0 }  # Detect profile sections
inside_profiles && /^\s*\[\[default\]\]/ { inside_default=1; print; next }
inside_profiles && inside_default && /^\s*cursor_shape\s*=/ { found_cursor=1 }
inside_profiles && inside_default && /^\s*font\s*=/ { found_font=1 }
inside_profiles && inside_default && /^\s*use_system_font\s*=/ { found_system_font=1 }
{ print }
END {
    if (!inside_profiles) print "[profiles]"
    if (!inside_default) print "  [[default]]"
    if (!found_cursor) print "    cursor_shape = underline"
    if (!found_font) print "    font = MesloLGLDZ Nerd Font 10"
    if (!found_system_font) print "    use_system_font = False"
}' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

show_header "Fixing file ownership for user configurations..."
log_and_run "fix_permissions" "chown -R $CURRENT_USER:$CURRENT_USER $USER_HOME/.config $USER_HOME/.local"

show_header "✅ Setup Complete!\n  You may want to restart this terminal\n  and/or the computer."

