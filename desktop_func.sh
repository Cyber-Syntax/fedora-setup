#!/bin/bash

#TODO: Need to automate update to ollama?
install_ollama() {
  echo "Setting up Ollama..."
  curl -fsSL https://ollama.com/install.sh | sed s/--add-repo/addrepo/ | sh
  echo "Ollama setup completed."
}
