#!/usr/bin/env bash
set -euo pipefail

# Define script names
SCRIPT_NAMES=("one.sh" "two.sh" "three.sh")

# Get today's day number (1–366)
DAY_NUMBER=$(date +%j)

# Compute index
INDEX=$(( (DAY_NUMBER - 1) % ${#SCRIPT_NAMES[@]} ))

# Pick the script name
SELECTED_SCRIPT_NAME=${SCRIPT_NAMES[$INDEX]}

# Get the corresponding URL from environment variables
if [ "$INDEX" -eq 0 ]; then
    TARGET_URL="${SCRIPT_URL_ONE:-}"
elif [ "$INDEX" -eq 1 ]; then
    TARGET_URL="${SCRIPT_URL_TWO:-}"
else
    TARGET_URL="${SCRIPT_URL_THREE:-}"
fi

echo "-----------------------------------"
echo " Date: $(date)"
echo " Day number: $DAY_NUMBER"
echo " Selected script name: $SELECTED_SCRIPT_NAME"
echo "-----------------------------------"

if [ -z "$TARGET_URL" ]; then
    echo "ERROR: No URL provided for $SELECTED_SCRIPT_NAME (SCRIPT_URL_... is empty)"
    exit 1
fi

echo "Fetching script from: $TARGET_URL"

# Logic to fetch the script
if [[ "$TARGET_URL" == *".git" ]]; then
    echo "Detected Git repository URL."
    TEMP_DIR="temp_script_repo"
    rm -rf "$TEMP_DIR"

    echo "Cloning repository..."
    git clone --depth 1 "$TARGET_URL" "$TEMP_DIR"

    # Try to find the exact script name first
    if [ -f "$TEMP_DIR/$SELECTED_SCRIPT_NAME" ]; then
        echo "Found $SELECTED_SCRIPT_NAME in repository."
        mv "$TEMP_DIR/$SELECTED_SCRIPT_NAME" .
    else
        echo "WARNING: $SELECTED_SCRIPT_NAME not found in the repository root."
        # Fallback: Look for *any* .sh file if the specific one isn't there?
        # Or maybe the repo IS the script context?
        # Based on instructions, we expect the script file to be there.
        # Let's check if there's a unique .sh file as a fallback
        FOUND_SH=$(find "$TEMP_DIR" -maxdepth 1 -name "*.sh" | head -n 1)
        if [ -n "$FOUND_SH" ]; then
            echo "Fallback: Found script $(basename "$FOUND_SH"). using it as $SELECTED_SCRIPT_NAME"
            mv "$FOUND_SH" "./$SELECTED_SCRIPT_NAME"
        else
            echo "ERROR: No suitable script found in repository."
            ls -R "$TEMP_DIR"
            exit 1
        fi
    fi

    # Clean up
    rm -rf "$TEMP_DIR"
else
    echo "Detected direct download URL."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$SELECTED_SCRIPT_NAME" "$TARGET_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$SELECTED_SCRIPT_NAME" "$TARGET_URL"
    else
        echo "ERROR: Neither curl nor wget found."
        exit 1
    fi
fi

# Ensure the script is executable
if [ -f "./$SELECTED_SCRIPT_NAME" ]; then
    chmod +x "./$SELECTED_SCRIPT_NAME"
    echo "Successfully fetched $SELECTED_SCRIPT_NAME"

    # Run the selected script
    echo "Executing ./$SELECTED_SCRIPT_NAME ..."
    "./$SELECTED_SCRIPT_NAME"
else
    echo "ERROR: Failed to fetch script file."
    exit 1
fi
