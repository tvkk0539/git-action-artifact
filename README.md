# Docker Automation & Sessions Artifact Scripts

This project automates the deployment and execution of Docker containers for specific tasks, with a built-in rotation system and artifact extraction capabilities. It is designed to run locally or via GitHub Actions.

## Project Structure

*   **`one.sh`, `two.sh`, `three.sh`**: The core worker scripts. Each script:
    1.  Clones a specific repository (`...-of-one`, `...-of-two`, etc.).
    2.  Builds a Docker image (with retries and fallbacks).
    3.  Runs the container in the background.
    4.  **New Feature**: Waits for a configurable delay, copies the `sessions` folder from the container, zips it, and prepares it for upload.
*   **`script.sh`**: A rotation script that selects which worker script (`one.sh`, `two.sh`, or `three.sh`) to run based on the day of the year.
*   **`.github/workflows/daily.yml`**: The GitHub Actions workflow that runs this process on a schedule (daily at 13:30 IST) or manually.

## Features

### 1. Automatic Sessions Extraction
The scripts are designed to extract valuable session data from the running container.
*   **How it works**: When the container starts, a background timer starts. After a specified delay, the script copies the `/usr/src/microsoft-rewards-script/dist/browser/sessions` folder from the container to the host.
*   **Artifact Upload**: In GitHub Actions, this folder is zipped (`sessions.zip`) and uploaded as a build artifact, allowing you to download and inspect the sessions later.

### 2. Session Restore (New)
You can restore a previously saved sessions folder into the container at startup.
*   **Enable**: Set `ENABLE_SESSION_RESTORE` to `true`.
*   **Source**: Provide the download URL via `SESSION_RESTORE_URL_ONE`, `_TWO`, or `_THREE`.
*   **Process**: The script downloads the zip, handles the nested structure (`sessions-zip/sessions.zip/sessions`), and mounts it to the container at `/usr/src/microsoft-rewards-script/dist/browser/sessions`.
*   **Note**: When Restore is enabled, Upload should generally be disabled (or will effectively be disabled if you set the toggle).

### 3. Robust Build System
The scripts include a multi-phase build process:
*   **Phase 1**: Attempts a standard `docker build`.
*   **Phase 2**: If standard build fails, it attempts to "fix" the environment by increasing timeouts, pre-pulling base images, and using BuildKit.

### 3. Daily Rotation
To distribute load or manage multiple accounts, `script.sh` automatically rotates between the three scripts based on the day number (Day 1 -> `one.sh`, Day 2 -> `two.sh`, etc.).

## Configuration

You can configure the behavior using Environment Variables.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `ENABLE_SESSION_UPLOAD`| Set to `true` to enable session artifact upload. Set to `false` to disable. | `false` (in script), `true` (in workflow) |
| `ENABLE_SESSION_RESTORE`| Set to `true` to enable session restore. | `false` |
| `SESSION_RESTORE_URL_...`| URL to download the sessions zip (ONE, TWO, or THREE). | `""` |
| `SESSION_COPY_DELAY` | Time in seconds to wait after container start before copying the sessions folder. | `300` (5 minutes) |
| `MIN_SLEEP_MINUTES` | passed to container | `1` |
| `MAX_SLEEP_MINUTES` | passed to container | `2` |

## How to Run

### Locally
To run a specific script (e.g., `one.sh`):

```bash
# Run and copy sessions after 1 minute (60s)
export SESSION_COPY_DELAY=60
./one.sh
```

To run the rotation script:
```bash
./script.sh
```

### GitHub Actions
The workflow is defined in `.github/workflows/daily.yml`.
1.  Go to the "Actions" tab in your repository.
2.  Select "007-of-one Docker Cycle".
3.  Click "Run workflow".
4.  Once finished, look for the **sessions-zip** in the "Artifacts" section of the run summary.
