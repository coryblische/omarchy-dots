#!/bin/bash

config_file="$HOME/.config/cava/config"

if [[ ! -f "$config_file" ]]; then
  exit 0
fi

# Make Cava consume the palette rendered by Aether.
if ! grep -q "^theme = 'aether'" "$config_file"; then
  sed -i "/^theme = /d" "$config_file"
  sed -i "/^\[color\]/a theme = 'aether'" "$config_file"
fi

# Reload colors without restarting audio processing when Cava is running.
if pgrep -x cava >/dev/null; then
  pkill -USR2 cava
fi
