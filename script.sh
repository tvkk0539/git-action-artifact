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

# Determine source type for logging
SOURCE_TYPE="Unknown"
if [[ "$TARGET_URL" == *".git" ]]; then
    SOURCE_TYPE="Git Repository"
elif [ -n "$TARGET_URL" ]; then
    SOURCE_TYPE="Direct Download"
else
    SOURCE_TYPE="None"
fi

echo "-----------------------------------"
echo " Today is Day $DAY_NUMBER (Index $INDEX)"
echo " Target Script: $SELECTED_SCRIPT_NAME"
echo " Source Type: $SOURCE_TYPE"
echo " Source URL: $TARGET_URL"
echo "-----------------------------------"

if [ -z "$TARGET_URL" ]; then
    echo "ERROR: No URL provided for $SELECTED_SCRIPT_NAME (SCRIPT_URL_... is empty)"
    exit 1
fi

echo "Fetching script from: $TARGET_URL"

# Logic to fetch and execute the script
if [[ "$TARGET_URL" == *".git" ]]; then
    echo "Detected Git repository URL."
    TEMP_DIR="fetched_repo"
    rm -rf "$TEMP_DIR"

    echo "Cloning repository..."
    git clone --depth 1 "$TARGET_URL" "$TEMP_DIR"

    # Enter the repo directory
    cd "$TEMP_DIR"
    echo "Entered repository directory: $(pwd)"

    SCRIPT_TO_RUN="./$SELECTED_SCRIPT_NAME"

    # Check if the specific script exists
    if [ ! -f "$SCRIPT_TO_RUN" ]; then
        echo "WARNING: $SELECTED_SCRIPT_NAME not found in the repository root."
        # Fallback: Look for *any* .sh file
        FOUND_SH=$(find . -maxdepth 1 -name "*.sh" | head -n 1)
        if [ -n "$FOUND_SH" ]; then
            echo "Fallback: Found script $(basename "$FOUND_SH"). Using it."
            SCRIPT_TO_RUN="$FOUND_SH"
        else
            echo "ERROR: No suitable script found in repository."
            ls -R .
            exit 1
        fi
    fi

    # Make executable
    chmod +x "$SCRIPT_TO_RUN"

    echo "Executing $SCRIPT_TO_RUN inside $(pwd)..."
    "$SCRIPT_TO_RUN"

    # Note: We do not clean up TEMP_DIR here because the script might have launched background processes
    # (like the docker session uploader) that rely on files here.
    # Or, if the script finishes, we could clean up.
    # Given the container logic, the script usually waits for docker wait.
    # So it is safe to just exit here. Cleanup will happen on next run or runner termination.

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
fi
