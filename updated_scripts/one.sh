#!/usr/bin/env bash
set -e

# --- MODIFICATION START: "Clone Once" Compatibility ---
# This script has been modified to work with the new script.sh "Clone Once" logic.
# 1. Removed `git clone`.
# 2. Removed `cd /tmp/repo`.
# 3. Artifact moves to `../` (Runner Root) instead of `$START_DIR` (Repo Root).
# ------------------------------------------------------

# Capture starting directory (which is now the fetched_repo)
START_DIR=$(pwd)

# --- USER CONFIGURATION (Overrides YAML/Secrets) ---
# Set these to "true", "false", or a number to FORCE a behavior.
# Leave them empty "" to respect the GitHub Workflow/YAML settings.
FORCE_ENABLE_UPLOAD=""
FORCE_ENABLE_RESTORE=""
FORCE_COPY_DELAY=""
# ---------------------------------------------------

# Apply Overrides
if [ -n "$FORCE_ENABLE_UPLOAD" ]; then
    echo "Configuration Override: ENABLE_SESSION_UPLOAD set to $FORCE_ENABLE_UPLOAD"
    ENABLE_SESSION_UPLOAD="$FORCE_ENABLE_UPLOAD"
fi

if [ -n "$FORCE_ENABLE_RESTORE" ]; then
    echo "Configuration Override: ENABLE_SESSION_RESTORE set to $FORCE_ENABLE_RESTORE"
    ENABLE_SESSION_RESTORE="$FORCE_ENABLE_RESTORE"
fi

if [ -n "$FORCE_COPY_DELAY" ]; then
    echo "Configuration Override: SESSION_COPY_DELAY set to $FORCE_COPY_DELAY"
    SESSION_COPY_DELAY="$FORCE_COPY_DELAY"
fi

# Default variables
ENABLE_RESTORE=${ENABLE_SESSION_RESTORE:-false}

# You can paste your URL directly here inside the quotes as a fallback
HARDCODED_RESTORE_URL=""

# Use Secret if available, otherwise use Hardcoded
RESTORE_URL=${SESSION_RESTORE_URL_ONE:-$HARDCODED_RESTORE_URL}
MOUNT_ARG=""

# --- Logic for Session Restore ---
if [ "$ENABLE_RESTORE" = "true" ]; then
    echo "=== Session Restore Feature ENABLED ==="

    if [ -z "$RESTORE_URL" ]; then
        echo "ERROR: ENABLE_SESSION_RESTORE is true, but SESSION_RESTORE_URL_ONE (Secret) and HARDCODED_RESTORE_URL are both empty!"
        exit 1
    fi

    echo "Downloading sessions from: $RESTORE_URL"
    # Create a temporary directory for extraction
    mkdir -p temp_restore

    if command -v curl >/dev/null 2>&1; then
        curl -L -o temp_restore/downloaded.zip "$RESTORE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O temp_restore/downloaded.zip "$RESTORE_URL"
    else
        echo "ERROR: Neither curl nor wget found. Cannot download sessions."
        exit 1
    fi

    echo "Unzipping downloaded file..."
    # 1. Unzip the main artifact (e.g., sessions-zip.zip)
    unzip -q temp_restore/downloaded.zip -d temp_restore/step1

    # 2. Find the inner zip (was specific "sessions.zip", now smart "*.zip")
    # The structure described: sessions-zip/ANY_NAME.zip
    INNER_ZIP=$(find temp_restore/step1 -name "*.zip" | head -n 1)

    if [ -z "$INNER_ZIP" ]; then
        echo "ERROR: Could not find any .zip file inside the downloaded artifact."
        echo "Contents of download:"
        ls -R temp_restore/step1
        exit 1
    fi

    echo "Found inner zip: $INNER_ZIP"
    unzip -q "$INNER_ZIP" -d temp_restore/step2

    # 3. Find the final 'sessions' folder
    # The structure described: .../sessions/sessions/
    FINAL_SESSIONS_DIR=$(find temp_restore/step2 -type d -name "sessions" | head -n 1)

    if [ -z "$FINAL_SESSIONS_DIR" ]; then
         echo "ERROR: Could not find a 'sessions' directory inside the inner zip."
         ls -R temp_restore/step2
         exit 1
    fi

    echo "Found sessions directory: $FINAL_SESSIONS_DIR"

    # Move it to a clean location for mounting
    rm -rf final_sessions
    mv "$FINAL_SESSIONS_DIR" ./final_sessions

    echo "Ready to mount ./final_sessions to container."
    MOUNT_ARG="-v $(pwd)/final_sessions:/usr/src/microsoft-rewards-script/dist/browser/sessions"

    # Cleanup temp
    rm -rf temp_restore
else
    echo "Session Restore Feature DISABLED."
fi


# Common function to run container (defined FIRST)
run_container() {
    echo -e "\n=== Running Container ==="
    echo "Running with custom flags:"
    echo "  --shm-size=4g"
    echo "  -e MIN_SLEEP_MINUTES=1"
    echo "  -e MAX_SLEEP_MINUTES=2"

    if [ -n "$MOUNT_ARG" ]; then
        echo "  $MOUNT_ARG"
    fi

    # Run container in detached mode
    CONTAINER_ID=$(docker run -d \
      --shm-size=4g \
      -e MIN_SLEEP_MINUTES=1 \
      -e MAX_SLEEP_MINUTES=2 \
      $MOUNT_ARG \
      myimage:latest)

    echo "Container started with ID: $CONTAINER_ID"

    # Start background process to copy sessions folder after delay (ONLY IF ENABLED)
    BG_PID=""
    if [ "$ENABLE_SESSION_UPLOAD" = "true" ]; then
        (
            COPY_DELAY=${SESSION_COPY_DELAY:-300} # Default 300s
            echo "Background timer started. Waiting ${COPY_DELAY}s before copying sessions..."
            sleep $COPY_DELAY

            echo "Time reached. Attempting to copy sessions folder..."
            if docker cp "$CONTAINER_ID:/usr/src/microsoft-rewards-script/dist/browser/sessions" ./sessions; then
                echo "Successfully copied sessions folder."
            else
                echo "Failed to copy sessions folder (container might be gone or path invalid)."
            fi
        ) &
        BG_PID=$!
    else
        echo "Session upload feature is DISABLED. Skipping background timer."
    fi

    # Stream logs to console so we can see what's happening
    docker logs -f $CONTAINER_ID

    # Wait for container to finish
    docker wait $CONTAINER_ID

    # Kill the background timer if it was started and is still running
    if [ -n "$BG_PID" ]; then
        kill $BG_PID 2>/dev/null || true
    fi

    echo "Container execution finished."

    # Zip the sessions folder IF enabled AND it exists
    if [ "$ENABLE_SESSION_UPLOAD" = "true" ]; then
        if [ -d "sessions" ]; then
            echo "Sessions folder found (timer triggered). Zipping..."
            if command -v zip >/dev/null 2>&1; then
                zip -r sessions.zip sessions
            else
                echo "zip command not found, trying tar..."
                tar -czf sessions.zip sessions
            fi

            # --- MODIFICATION: Move Artifact to Runner Root (Up one level) ---
            # Was: mv sessions.zip "$START_DIR/"
            mv sessions.zip ../
            echo "Artifact moved to runner root (../sessions.zip)"
            # -----------------------------------------------------------------

            # --- Artifact Naming Logic ---
            # Default to timestamped name to prevent overwrites when fallback is used
            ARTIFACT_NAME="sessions_$(date +%Y%m%d_%H%M%S)"

            if [ -n "$ARTIFACT_NAME_CUSTOM" ]; then
                 ARTIFACT_NAME="$ARTIFACT_NAME_CUSTOM"
                 echo "Using custom artifact name: $ARTIFACT_NAME"
            elif [ -n "$ACCOUNT_1" ]; then
                 # Sanitize email/account name (replace @ with _, remove spaces/special chars)
                 SANITIZED_ACC=$(echo "$ACCOUNT_1" | tr '@' '_' | tr -cd '[:alnum:]_.-')
                 ARTIFACT_NAME="$SANITIZED_ACC"
                 echo "Using account-based artifact name: $ARTIFACT_NAME"
            fi

            # Export to GITHUB_ENV so the upload step can see it
            echo "DEBUG: Exporting ARTIFACT_CREATED=true to $GITHUB_ENV"
            echo "ARTIFACT_NAME=$ARTIFACT_NAME" >> $GITHUB_ENV
            echo "ARTIFACT_CREATED=true" >> $GITHUB_ENV

            # --- MODIFICATION: Upload to Discord if configured ---
            if [ -n "$DISCORD_WEBHOOK_URL" ]; then
                echo "Uploading artifact to Discord..."
                curl -v \
                  -F "payload_json={\"content\": \"✅ Session Backup: $ARTIFACT_NAME\"}" \
                  -F "file=@../sessions.zip" \
                  "$DISCORD_WEBHOOK_URL" || echo "Discord upload failed."
                echo ""
            fi
            # -----------------------------------------------------
        else
            echo "Sessions folder NOT found. Container finished before copy delay ($SESSION_COPY_DELAY s) or copy failed."
            echo "Skipping artifact creation."
        fi
    fi

    # Cleanup
    echo "Cleaning up container..."
    docker rm -f $CONTAINER_ID || true

    # Cleanup restore folder if it exists
    rm -rf final_sessions
}

# --- MODIFICATION: Removed Git Clone ---
# Was: git clone ...
# Was: cd /tmp/repo
# Now: We assume we are already in the correct directory.
# ---------------------------------------

# Extract base image from Dockerfile
if [ ! -f "Dockerfile" ]; then
    echo "ERROR: Dockerfile not found!"
    exit 1
fi

# Find the FROM line and extract the image name
BASE_IMAGE=$(grep -m1 '^FROM' Dockerfile | sed 's/^FROM //' | tr -d '[:space:]')

if [ -z "$BASE_IMAGE" ]; then
    echo "ERROR: Could not find base image in Dockerfile!"
    exit 1
fi

echo "Found base image in Dockerfile: $BASE_IMAGE"

echo "=== Phase 1: Try normal build first ==="
NORMAL_SUCCESS=false

# Try normal build 3 times
for attempt in {1..3}; do
    echo "Normal build attempt $attempt of 3..."
    if docker build -t myimage:latest .; then
        echo "✅ Normal build successful!"
        NORMAL_SUCCESS=true
        break
    else
        if [ $attempt -lt 3 ]; then
            echo "Normal build failed, retrying in 5 seconds..."
            sleep 5
        fi
    fi
done

# If normal build succeeded, skip to run
if [ "$NORMAL_SUCCESS" = true ]; then
    echo "Build successful! Proceeding to run..."
    run_container
    exit 0
fi

echo -e "\n=== Phase 2: Normal build failed, trying optimized approach ==="

# 1. Increase Docker timeouts
echo "Increasing Docker timeouts..."
sudo tee /etc/docker/daemon.json << EOF
{
  "max-concurrent-downloads": 1,
  "max-download-attempts": 5,
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
sudo systemctl restart docker || sudo service docker restart

# 2. Pre-pull the base image with retry (using extracted image name)
echo "Pre-pulling base image..."
echo "Base image to pull: $BASE_IMAGE"

for attempt in {1..5}; do
    echo "Pull attempt $attempt of 5..."
    if docker pull "$BASE_IMAGE"; then
        echo "Successfully pulled base image"
        break
    else
        if [ $attempt -eq 5 ]; then
            echo "All pull attempts failed. Trying alternative approach..."
            # Continue anyway, build might use cache
        else
            echo "Pull failed, retrying in 15 seconds..."
            sleep 15
        fi
    fi
done

# 3. Build with retry logic
echo "Building Docker image..."
for attempt in {1..3}; do
    echo "Build attempt $attempt of 3..."

    # Enable BuildKit for better caching
    DOCKER_BUILDKIT=1 docker build \
        --progress=plain \
        --no-cache \
        -t myimage:latest . && break

    if [ $attempt -lt 3 ]; then
        echo "Build failed, cleaning cache and retrying in 10 seconds..."
        docker builder prune -f
        sleep 10
    else
        echo "All build attempts failed!"
        exit 1
    fi
done

echo "Build successful!"

# Call the common run function
run_container
