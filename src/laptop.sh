#!/usr/bin/env bash

source src/logging.sh
source src/variables.sh

laptop_hostname_change() {
  log_info "Changing hostname for laptop..."

  # Execute command directly instead of using log_cmd
  if ! hostnamectl set-hostname "$hostname_laptop"; then
    log_error "Failed to change hostname"
    return 1
  fi

  log_info "Hostname changed to $hostname_laptop."
}

tlp_setup() {
  log_info "Setting up TLP for power management..."

  # Capture Fedora version once
  local fedora_version
  fedora_version=$(awk '{print $3}' /etc/fedora-release)
  log_debug "Detected Fedora version: $fedora_version"

  # Make sure tlp is installed, if not install it
  if ! rpm -q tlp &>/dev/null; then
    log_info "TLP is not installed. Installing..."
    if ! sudo dnf install -y tlp; then
      log_error "Failed to install TLP"
      return 1
    fi
  fi

  local tlp_file="./configs/01-mytlp.conf"
  local dir_tlp="/etc/tlp.d/01-mytlp.conf"

  # Create the tlp.d directory if it doesn't exist
  if [[ ! -d "/etc/tlp.d" ]]; then
    if ! sudo mkdir -p /etc/tlp.d; then
      log_error "Failed to create /etc/tlp.d directory"
      return 1
    fi
  fi
  
  # Backup if there is no backup
  if [[ ! -f "/etc/tlp.d/01-mytlp.conf.bak" ]]; then
    if ! sudo cp /etc/tlp.d/01-mytlp.conf /etc/tlp.d/01-mytlp.conf.bak; then
      log_warn "Failed to create backup of TLP configuration"
    fi
  fi

  # Copy the TLP configuration file
  if ! sudo cp "$tlp_file" "$dir_tlp"; then
    log_error "Failed to copy TLP configuration file"
    return 1
  fi

  # 2. Service management with existence checks
  handle_services() {
    local action="$1"
    shift
    for service in "$@"; do
      if systemctl list-unit-files | grep -q "^$service"; then
        if ! systemctl "$action" "$service"; then
          log_warn "Failed to $action $service"
        fi
      else
        log_debug "Service $service not found - skipping"
      fi
    done
  }

  # 3. TuneD handling
  if ((fedora_version > 40)); then
    log_info "Handling TuneD for Fedora $fedora_version..."
    handle_services 'disable --now' tuned tuned-ppd

    if rpm -q tuned tuned-ppd &>/dev/null; then
      if ! sudo dnf remove -y tuned tuned-ppd; then
        log_error "Failed to remove TuneD packages"
        return 1
      fi
    fi
  fi

  # 4. power-profile-daemon handling
  if ((fedora_version < 41)); then
    log_info "Handling power-profile-daemon for Fedora $fedora_version..."
    handle_services 'disable --now' power-profile-daemon

    if rpm -q power-profile-daemon &>/dev/null; then
      if ! sudo dnf remove -y power-profile-daemon; then
        log_error "Failed to remove power-profile-daemon"
        return 1
      fi
    fi
  fi

  # 5. Enable TLP services with verification
  log_info "Configuring TLP services..."
  for service in tlp tlp-sleep; do
    if [[ -f "/usr/lib/systemd/system/${service}.service" ]]; then
      if ! sudo systemctl enable --now "$service"; then
        log_error "Failed to enable $service"
        return 1
      fi
    else
      log_warn "$service service not found"
    fi
  done

  # mask rfkill to be able to handle radios with tlp
  if ! sudo systemctl mask systemd-rfkill.service; then
    log_warn "Failed to mask systemd-rfkill.service"
  fi

  if ! sudo systemctl mask systemd-rfkill.socket; then
    log_warn "Failed to mask systemd-rfkill.socket"
  fi

  # enable tlp radio device handling
  if ! sudo tlp-rdw enable; then
    log_warn "Failed to enable TLP radio device handling"
  fi

  log_info "TLP setup completed successfully."
  return 0
}

thinkfan_setup() {
  log_info "Setting up thinkfan for fan control..."

  local dir_thinkfan="/etc/thinkfan.conf"
  local thinkfan_file="./configs/thinkfan.conf"

  # backup if there is no backup
  if [[ ! -f "/etc/thinkfan.conf.bak" ]]; then
    if ! sudo cp /etc/thinkfan.conf /etc/thinkfan.conf.bak; then
      log_warn "Failed to create backup of thinkfan configuration"
    fi
  fi

  if ! sudo cp "$thinkfan_file" "$dir_thinkfan"; then
    log_error "Failed to copy thinkfan configuration file"
    return 1
  fi

  # Modprobe thinkpad_acpi
  log_debug "Setting thinkpad_acpi module options..."
  if ! echo "options thinkpad_acpi fan_control=1 experimental=1" | sudo tee /etc/modprobe.d/thinkfan.conf >/dev/null; then
    log_error "Failed to create thinkpad_acpi options file"
    return 1
  fi

  if ! modprobe -rv thinkpad_acpi; then
    log_warn "Failed to remove thinkpad_acpi module"
  fi

  if ! modprobe -v thinkpad_acpi; then
    log_warn "Failed to load thinkpad_acpi module"
  fi

  log_info "Enabling and starting thinkfan services..."
  sudo systemctl enable --now thinkfan || log_warn "Failed to enable and start thinkfan service"
  sudo systemctl enable thinkfan-sleep || log_warn "Failed to enable thinkfan-sleep service"
  sudo systemctl enable thinkfan-wakeup || log_warn "Failed to enable thinkfan-wakeup service"

  # thinkfan sleep hack for 100% fan usage on suspend
  local thinkfan_sleep_hack="/etc/systemd/system/thinkfan-sleep-hack.service"
  log_debug "Creating thinkfan sleep hack service at $thinkfan_sleep_hack..."

  cat <<EOF | sudo tee "$thinkfan_sleep_hack" >/dev/null
[Unit]
Description=Set fan to auto so BIOS can shut off fan during S2 sleep
Before=sleep.target
After=thinkfan-sleep.service

[Service]
Type=oneshot
ExecStart=/usr/bin/logger -t '%N' "Setting /proc/acpi/ibm/fan to 'level auto'"
ExecStart=/usr/bin/bash -c '/usr/bin/echo "level auto" > /proc/acpi/ibm/fan'

[Install]
WantedBy=sleep.target
EOF

  if [ $? -ne 0 ]; then
    log_error "Failed to create thinkfan-sleep-hack service file"
    return 1
  fi

  log_info "Enabling thinkfan-sleep-hack service..."
  if ! sudo systemctl enable thinkfan-sleep-hack; then
    log_warn "Failed to enable thinkfan-sleep-hack service"
  fi

  log_info "Thinkfan setup completed successfully."
}

xorg_setup_intel() {
  log_info "Setting up xorg configuration..."

  local intel_file="./configs/20-intel.conf"
  local dir_intel="/etc/X11/xorg.conf.d/20-intel.conf"

  # Execute commands directly instead of using log_cmd
  if ! sudo cp "$intel_file" "$dir_intel"; then
    log_error "Failed to copy Intel configuration file"
    return 1
  fi
  
  local dir_touchpad="/etc/X11/xorg.conf.d/99-touchpad.conf"
  local touchpad_file="./configs/99-touchpad.conf"

  if ! sudo cp "$touchpad_file" "$dir_touchpad"; then
    log_error "Failed to copy touchpad configuration file"
    return 1
  fi

  log_info "Xorg configuration completed."
}

# Udev rules for brightness control on qtile
install_qtile_udev_rule() {
  log_info "Setting up udev rule for qtile..."

  local dir_qtile_rules="/etc/udev/rules.d/99-qtile.rules"
  local qtile_rules_file="./configs/99-qtile.rules"
  local dir_backlight="/etc/X11/xorg.conf.d/99-backlight.conf"
  local backlight_file="./configs/99-backlight.conf"

  # Execute commands directly instead of using log_cmd
  if ! sudo cp "$qtile_rules_file" "$dir_qtile_rules"; then
    log_error "Failed to copy udev rule for qtile"
    return 1
  fi

  log_info "Udev rule for qtile setup completed."

  # copy intel_backlight to xorg.conf.d
  if ! sudo cp "$backlight_file" "$dir_backlight"; then
    log_error "Failed to copy backlight configuration"
    return 1
  fi

  log_info "Backlight configuration completed."

  # reload udev rules
  if ! sudo udevadm control --reload-rules && sudo udevadm trigger; then
    log_error "Failed to reload udev rules"
    return 1
  fi

  log_info "Udev rules reloaded."
}

touchpad_setup() {
  log_info "Setting up touchpad configuration..."

  # Create the touchpad configuration file as user
  if ! sudo cp "$touchpad_file" "$dir_touchpad"; then
    log_error "Failed to copy touchpad configuration"
    return 1
  fi

  log_info "Touchpad configuration completed."
}

# sshd setup, copy ssh keys to laptop from desktop etc.
ssh_setup_laptop() {
  log_info "Setting up SSH for laptop"

  # Enable password authentication to be able to receive keys
  if ! sudo systemctl enable --now sshd; then
    log_error "Failed to enable SSH service"
    return 1
  fi

  # Write sshd config to allow password authentication
  #TODO: Add some security here
  cat <<EOF >/etc/ssh/sshd_config.d/temp_password_auth.conf
PasswordAuthentication yes
PermitRootLogin no
PermitEmptyPasswords yes
EOF
  log_info "SSH password authentication enabled for laptop."
  log_info "Setting up SSH..."

  # TODO: need to create keys but if they are not created yet.
  # NOTE: desktop sends keys to laptop here
  if ! ssh-copy-id $USER@$LAPTOP_IP; then
    log_error "Failed to copy SSH keys to laptop"
    return 1
  fi

  log_info "SSH keys copied successfully."
}