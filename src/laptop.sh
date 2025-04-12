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
  # Capture Fedora version once
  local fedora_version
  fedora_version=$(awk '{print $3}' /etc/fedora-release)
  echo "Detected Fedora version: $fedora_version"

  if ! sudo cp "$tlp_file" "$dir_tlp"; then
    echo "Error: Failed to copy TLP configuration file" >&2
    return 1
  fi

  # 2. Service management with existence checks
  handle_services() {
    local action="$1"
    shift
    for service in "$@"; do
      if systemctl list-unit-files | grep -q "^$service"; then
        systemctl "$action" "$service" || echo "Warning: Failed to $action $service" >&2
      else
        echo "Service $service not found - skipping"
      fi
    done
  }

  # 3. TuneD handling
  if ((fedora_version > 40)); then
    echo "Handling TuneD for Fedora $fedora_version..."
    handle_services 'disable --now' tuned tuned-ppd

    if rpm -q tuned tuned-ppd &>/dev/null; then
      if ! sudo dnf remove -y tuned tuned-ppd; then
        echo "Error: Failed to remove TuneD packages" >&2
        return 1
      fi
    fi
  fi

  # 4. power-profile-daemon handling
  if ((fedora_version < 41)); then
    echo "Handling power-profile-daemon for Fedora $fedora_version..."
    handle_services 'disable --now' power-profile-daemon

    if rpm -q power-profile-daemon &>/dev/null; then
      if ! sudo dnf remove -y power-profile-daemon; then
        echo "Error: Failed to remove power-profile-daemon" >&2
        return 1
      fi
    fi
  fi

  # 5. Enable TLP services with verification
  echo "Configuring TLP services..."
  for service in tlp tlp-sleep; do
    if [[ -f "/usr/lib/systemd/system/${service}.service" ]]; then
      if ! sudo systemctl enable --now "$service"; then
        echo "Error: Failed to enable $service" >&2
        return 1
      fi
    else
      echo "Warning: $service service not found" >&2
    fi
  done

  # mask rfkill to be able to handle radios with tlp
  sudo systemctl mask systemd-rfkill.service
  sudo systemctl mask systemd-rfkill.socket

  # enable tlp radio device handling
  sudo tlp-rdw enable

  echo "TLP setup completed successfully."
  return 0
}

thinkfan_setup() {
  echo "Copying thinkfan configuration..."
  # backup if there is no backup
  if [[ ! -f "/etc/thinkfan.conf.bak" ]]; then
    sudo cp /etc/thinkfan.conf /etc/thinkfan.conf.bak
  fi

  if ! sudo cp "$thinkfan_file" "$dir_thinkfan"; then
    echo "Error: Failed to copy thinkfan configuration file" >&2
    return 1
  fi

  # Modprobe thinkpad_acpi
  echo "options thinkpad_acpi fan_control=1 experimental=1" | sudo tee /etc/modprobe.d/thinkfan.conf
  modprobe -rv thinkpad_acpi
  modprobe -v thinkpad_acpi

  echo "Enabling and starting thinkfan service..."
  sudo systemctl enable --now thinkfan
  sudo systemctl enable thinkfan-sleep
  sudo systemctl enable thinkfan-wakeup

  #thinkfan sleep hack for %100 fan usage on suspend:
  local thinkfan_sleep_hack="/etc/systemd/system/thinkfan-sleep-hack.service"
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
  echo "Enabling thinkfan-sleep-hack service..."
  sudo systemctl enable thinkfan-sleep-hack

  echo "Thinkfan setup completed."
}

xorg_setup_intel() {
  log_info "Setting up xorg configuration..."

  # Execute commands directly instead of using log_cmd
  if ! sudo cp "$intel_file" "$dir_intel"; then
    log_error "Failed to copy Intel configuration file"
    return 1
  fi

  if ! sudo cp "$touchpad_file" "$dir_touchpad"; then
    log_error "Failed to copy touchpad configuration file"
    return 1
  fi

  log_info "Xorg configuration completed."
}

# Udev rules for brightness control on qtile
install_qtile_udev_rule() {
  log_info "Setting up udev rule for qtile..."

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
  sudo cp "$touchpad_file" "$dir_touchpad"

  log_info "Touchpad configuration completed."
}
