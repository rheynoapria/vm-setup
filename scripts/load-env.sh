#!/bin/bash
# Script to load environment variables from config file

# Default config file location
CONFIG_FILE="/opt/scripts/config/settings.env"
LOCAL_CONFIG_FILE="$(dirname "$(dirname "$(readlink -f "$0")")")/config/settings.env"

# Function to load environment variables
load_env() {
    local env_file="$1"
    
    if [ -f "$env_file" ]; then
        echo "Loading environment from $env_file"
        # Use a while loop to properly handle multi-line values
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            if [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Export the variable
            export "$line"
        done < "$env_file"
        return 0
    else
        echo "Environment file $env_file not found"
        return 1
    fi
}

# Try to load from installed location first, then from local directory
if ! load_env "$CONFIG_FILE"; then
    if ! load_env "$LOCAL_CONFIG_FILE"; then
        echo "WARNING: No configuration file found. Using default values."
    fi
fi 