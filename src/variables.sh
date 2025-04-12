#!/usr/bin/env bash

USER=$(whoami)  # automatically detect current user
# User-specific variables
# WARN: Change these variables as needed
# WARNING: Comment out the line below if you want to use the detected user.
SESSION="qtile"
LAPTOP_IP="192.168.1.54"

# Hostname
hostname_desktop="fedora"
hostname_laptop="fedora-laptop"

# Browser
PROFILE="sqwu9kep.default-release"
firefox_profile="/home/$USER/.mozilla/firefox/$PROFILE"
librewolf_dir="/home/$USER/.librewolf/"
librewolf_profile="/home/$USER/.librewolf/profiles.ini"

# Mirror
mirror_country="de"

# Global variables
# DNF repository directory used more than one function
REPO_DIR="/etc/yum.repos.d"