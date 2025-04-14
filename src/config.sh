#!/usr/bin/env bash

source src/logging.sh

# Function to check if configuration exists and create it with user permission
check_and_create_config() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fedora-setup"
    local packages_file="$config_dir/packages.json"
    local variables_file="$config_dir/variables.json"
    
    # Check if config directory exists
    if [[ ! -d "$config_dir" ]]; then
        echo -e "\n===== Configuration Setup ====="
        echo "This script needs to create a configuration directory at:"
        echo "  $config_dir"
        echo "This directory will store your settings and package lists."
        read -p "Allow creating this directory? [y/N] " answer
        echo
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            mkdir -p "$config_dir"
            log_info "Created configuration directory at $config_dir"
        else
            log_error "Cannot proceed without configuration directory"
            exit 1
        fi
    fi
    
    # Check if configuration files exist
    local files_needed=()
    [[ ! -f "$packages_file" ]] && files_needed+=("packages.json")
    [[ ! -f "$variables_file" ]] && files_needed+=("variables.json")
    
    # Only ask if there are files needed
    if [[ ${#files_needed[@]} -gt 0 ]]; then
        echo -e "\n===== Default Configuration ====="
        echo "The following configuration files need to be created:"
        for file in "${files_needed[@]}"; do
            echo "  - $config_dir/$file"
        done
        echo "These will contain default settings for your system."
        read -p "Create these files with default values? [y/N] " answer
        echo
        
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            # Create the files - check each creation
            for file in "${files_needed[@]}"; do
                if [[ "$file" == "packages.json" ]]; then
                    create_default_packages_json "$packages_file"
                    if [[ -f "$packages_file" ]]; then
                        echo "Created $file successfully."
                    else
                        log_error "Failed to create $file!"
                        exit 1
                    fi
                elif [[ "$file" == "variables.json" ]]; then
                    create_default_variables_json "$variables_file"
                    if [[ -f "$variables_file" ]]; then
                        echo "Created $file successfully."
                    else
                        log_error "Failed to create $file!"
                        exit 1
                    fi
                fi
            done
            
            echo -e "\n===== Configuration Created ====="
            echo "Default configuration files have been created."
            echo "You may want to review and customize them at:"
            echo "  $config_dir"
            echo
            read -p "Press Enter to continue or Ctrl+C to exit and edit them first" answer
            echo
        else
            log_error "Cannot proceed without configuration files"
            echo "You'll need to manually create the following files:"
            for file in "${files_needed[@]}"; do
                echo "  - $config_dir/$file"
            done
            exit 1
        fi
    fi
}

# Create JSON configuration handling function
load_json_config() {
    local config_file="$1"
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fedora-setup"
    local full_path="$config_dir/$config_file"
    
    # Check if the file exists first
    if [[ -f "$full_path" ]]; then
        echo "$full_path"
        return 0
    elif [[ -f "./configs/$config_file" ]]; then
        echo "./configs/$config_file"
        return 0
    fi
    
    # The file doesn't exist - handle creation
    echo -e "\nConfiguration file not found: $config_file"
    echo "Would you like to create it with default values?"
    read -p "[y/N] " answer
    echo
    
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        # Create directory if it doesn't exist
        mkdir -p "$config_dir"
        
        # Create default configuration
        case "$config_file" in
            "packages.json")
                create_default_packages_json "$full_path"
                ;;
            "variables.json")
                create_default_variables_json "$full_path"
                ;;
            *)
                echo "Unknown configuration file: $config_file" >&2
                return 1
                ;;
        esac
        
        # Verify the file was created
        if [[ -f "$full_path" ]]; then
            echo "Created default $config_file successfully."
            echo "$full_path"
            return 0
        else
            echo "ERROR: Failed to create $config_file" >&2
            return 1
        fi
    else
        echo "Cannot proceed without configuration file: $config_file" >&2
        exit 1
    fi
}

# Helper to parse JSON with jq
parse_json() {
    local json_file="$1"
    local jq_filter="$2"

    # Make sure the file exists
    if [[ ! -f "$json_file" ]]; then
        log_error "JSON file not found: $json_file"
        return 1
    fi

    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        echo "jq is required but not installed. Installing..." >&2
        read -p "Install jq now? [y/N] " answer
        echo
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sudo dnf install -y jq || {
                echo "Failed to install jq. Cannot parse JSON configuration." >&2
                return 1
            }
        else
            echo "Cannot proceed without jq." >&2
            exit 1
        fi
    fi

    # Parse the JSON file with jq
    jq -r "$jq_filter" "$json_file" || {
        log_error "Failed to parse JSON file: $json_file"
        return 1
    }
}

# Create default packages JSON
create_default_packages_json() {
    local output_file="$1"
    
    # Ensure directory exists
    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
    "core": [
        "curl",
        "wget",
        "ufw",
        "trash-cli",
        "syncthing",
        "borgbackup",
        "flatpak"
    ],
    "apps": [
        "seahorse",
        "xournalpp",
        "kitty",
        "keepassxc",
        "neovim",
        "vim",
        "pavucontrol"
    ],
    "dev": [
        "gh",
        "ruff",
        "lm_sensors",
        "htop",
        "btop",
        "pip",
        "zoxide",
        "fzf",
        "bat",
        "eza",
        "fd-find",
        "zsh-autosuggestions",
        "zsh-syntax-highlighting",
        "zsh",
        "luarocks",
        "cargo",
        "yarnpkg",
        "bash-language-server",
        "python3-devel",
        "dbus-devel",
        "shfmt",
        "ShellCheck"
    ],
    "desktop": [
        "virt-manager",
        "libvirt",
        "nvidia-open",
        "lightdm",
        "sysbench"
    ],
    "laptop": [
        "powertop",
        "tlp",
        "tlp-rdw",
        "thinkfan"
    ],
    "qtile": [
        "feh",
        "picom",
        "i3lock",
        "rofi",
        "qtile-extras",
        "lxappearance",
        "gammastep",
        "numlockx",
        "dunst",
        "flameshot",
        "playerctl",
        "xev"
    ],
    "flatpak": [
        "org.signal.Signal",
        "io.github.martchus.syncthingtray",
        "com.tutanota.Tutanota",
        "com.zed.Zed",
        "md.obsidian.Obsidian",
        "com.spotify.Client"
    ]
}
EOF

    # Check if the file was created successfully
    if [[ ! -f "$output_file" ]]; then
        log_error "Failed to create $output_file"
        return 1
    fi
    
    return 0
}

# Create default variables JSON
create_default_variables_json() {
    local output_file="$1"
    local current_user=$(whoami)
    
    # Ensure directory exists
    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" <<EOF
{
    "user": "$current_user",
    "session": "qtile",
    "laptop_ip": "192.168.1.54",
    "hostnames": {
        "desktop": "fedora",
        "laptop": "fedora-laptop"
    },
    "browser": {
        "firefox_profile": "sqwu9kep.default-release",
        "firefox_profile_path": "/home/$current_user/.mozilla/firefox/sqwu9kep.default-release",
        "librewolf_dir": "/home/$current_user/.librewolf/",
        "librewolf_profile": "/home/$current_user/.librewolf/profiles.ini"
    },
    "system": {
        "mirror_country": "de",
        "repo_dir": "/etc/yum.repos.d"
    }
}
EOF

    # Check if the file was created successfully
    if [[ ! -f "$output_file" ]]; then
        log_error "Failed to create $output_file"
        return 1
    fi
    
    return 0
}

# Load specific values from the variables.json file
load_variables() {
    log_info "Loading variables from configuration..."
    
    # First, make sure we have a variables file
    local variables_file=$(load_json_config "variables.json")
    
    if [[ -z "$variables_file" || ! -f "$variables_file" ]]; then
        log_error "Failed to load variables configuration"
        exit 1
    fi
    
    # Load all variables into Bash variables with proper error handling
    
    # Simple key-value pairs - mapping from snake_case in JSON to same in Bash
    USER=$(parse_json "$variables_file" ".user")
    SESSION=$(parse_json "$variables_file" ".session")
    LAPTOP_IP=$(parse_json "$variables_file" ".laptop_ip")
    
    # Nested values
    hostname_desktop=$(parse_json "$variables_file" ".hostnames.desktop")
    hostname_laptop=$(parse_json "$variables_file" ".hostnames.laptop")
    
    # Browser settings
    firefox_profile=$(parse_json "$variables_file" ".browser.firefox_profile")
    firefox_profile_path=$(parse_json "$variables_file" ".browser.firefox_profile_path")
    librewolf_dir=$(parse_json "$variables_file" ".browser.librewolf_dir")
    librewolf_profile=$(parse_json "$variables_file" ".browser.librewolf_profile")
    
    # System settings
    mirror_country=$(parse_json "$variables_file" ".system.mirror_country")
    REPO_DIR=$(parse_json "$variables_file" ".system.repo_dir")
    
    # Export all variables to make them available to the script
    export USER SESSION LAPTOP_IP hostname_desktop hostname_laptop
    export firefox_profile firefox_profile_path librewolf_dir librewolf_profile
    export mirror_country REPO_DIR
    
    log_info "Variables loaded successfully"
}

# Usage example for packages
load_packages() {
    local package_type="$1"
    local packages_file=$(load_json_config "packages.json")

    # Verify file exists
    if [[ -z "$packages_file" || ! -f "$packages_file" ]]; then
        log_error "Failed to load packages configuration"
        return 1
    fi

    # Parse the JSON to get the requested package list
    parse_json "$packages_file" ".${package_type} | join(\" \")"
}

# Usage example for variables
get_variable() {
    local var_path="$1"
    local variables_file=$(load_json_config "variables.json")

    # Verify file exists
    if [[ -z "$variables_file" || ! -f "$variables_file" ]]; then
        log_error "Failed to load variables configuration"
        return 1
    fi

    # Parse the JSON to get the requested variable
    parse_json "$variables_file" "$var_path"
}

# Load package arrays from JSON
load_package_arrays() {
    log_info "Loading package arrays from configuration..."
    
    # Get the packages file path
    local packages_file=$(load_json_config "packages.json")
    
    # Verify file exists
    if [[ -z "$packages_file" || ! -f "$packages_file" ]]; then
        log_error "Failed to load packages configuration"
        return 1
    fi
    
    # Load each package array from the JSON
    CORE_PACKAGES=($(parse_json "$packages_file" ".core[]"))
    APPS_PACKAGES=($(parse_json "$packages_file" ".apps[]"))
    DEV_PACKAGES=($(parse_json "$packages_file" ".dev[]"))
    DESKTOP_PACKAGES=($(parse_json "$packages_file" ".desktop[]"))
    LAPTOP_PACKAGES=($(parse_json "$packages_file" ".laptop[]"))
    QTILE_PACKAGES=($(parse_json "$packages_file" ".qtile[]"))
    FLATPAK_PACKAGES=($(parse_json "$packages_file" ".flatpak[]"))
    
    # Export all arrays to make them available to the script
    export CORE_PACKAGES APPS_PACKAGES DEV_PACKAGES 
    export DESKTOP_PACKAGES LAPTOP_PACKAGES
    export QTILE_PACKAGES FLATPAK_PACKAGES
    
    log_info "Package arrays loaded successfully"
}

# Modified install_qtile_packages that uses the loaded arrays
install_qtile_packages() {
  log_info "Installing Qtile packages..."
  
  # Install packages - using the loaded array
  sudo dnf install -y "${QTILE_PACKAGES[@]}" || {
    log_error "Failed to install Qtile packages."
    return 1
  }
  
  log_info "Qtile packages installed successfully"
}

# Function to initialize all configuration
init_config() {
    log_info "Initializing configuration..."
    
    # Check and create config if needed
    check_and_create_config
    
    # Load all configuration values
    load_variables
    load_package_arrays
    
    log_info "Configuration loaded successfully and ready to use"
    log_info "All package arrays and variables are now available"
    
    # Print a summary of the loaded configuration
    log_info "===== Configuration Summary ====="
    log_info "User: $USER"
    log_info "System Type: Based on hostname '$(hostname)'"
    log_info "  Desktop hostname: $hostname_desktop"
    log_info "  Laptop hostname: $hostname_laptop"
    log_info "Session: $SESSION"
    log_info "------------------------------"
    log_info "Core Packages: ${#CORE_PACKAGES[@]} packages"
    log_info "Qtile Packages: ${#QTILE_PACKAGES[@]} packages"
    log_info "Flatpak Packages: ${#FLATPAK_PACKAGES[@]} packages"
    log_info "Development Packages: ${#DEV_PACKAGES[@]} packages"
    log_info "Desktop Packages: ${#DESKTOP_PACKAGES[@]} packages"
    log_info "Laptop Packages: ${#LAPTOP_PACKAGES[@]} packages"
    log_info "===== End of Summary ====="
}

# Initialize configuration
init_config
