# Docker Automation & Sessions Artifact Scripts

This project automates the deployment and execution of Docker containers for specific tasks, with a built-in rotation system, artifact extraction, and automated release uploads. It is designed to run locally or via GitHub Actions.

## Project Structure

*   **`one.sh`, `two.sh`, `three.sh`**: The core worker scripts. Each script:
    1.  Clones a specific repository.
    2.  Builds a Docker image (with retries and fallbacks).
    3.  **Session Restore (Optional)**: Downloads a previous session zip and mounts it to the container at startup.
    4.  Runs the container in the background.
    5.  **Session Upload (Optional)**: Waits for a configurable delay (default 40 mins). If the container runs longer than this, it copies the `sessions` folder, zips it, and prepares it for upload. If the container finishes early, this step is skipped.
*   **`script.sh`**: A rotation script that selects which worker script to run based on the day of the year.
*   **Workflows**:
    *   `daily.yml`: Runs `007-of-one`.
    *   `alternate-1.yml`: Runs `007-of-two`.
    *   `alternate-2.yml`: Runs `007-of-three`.

## Features

### 1. Automatic Sessions Extraction (Artifacts & Releases)
Extracts valuable session data from the running container.
*   **Process**: When the container starts, a background timer starts. After `SESSION_COPY_DELAY` (default 40m), the script copies the sessions folder.
*   **Dynamic Naming**: The output zip is named based on:
    1.  `ARTIFACT_NAME_CUSTOM` (Manual override).
    2.  `ACCOUNT_1` / `ACCOUNT_2` / `ACCOUNT_3` (Sanitized email from secrets).
    3.  **Fallback**: `sessions_TIMESTAMP.zip`.
*   **Upload Methods**:
    *   **GitHub Artifacts**: Uploads the zip as a build artifact (retention 90 days). Controlled by `ENABLE_ARTIFACT_UPLOAD`.
    *   **GitHub Releases**: Uploads the zip to a release tag `project-007`. Controlled by `ENABLE_RELEASE_UPLOAD`.

### 2. Session Restore (Smart Restore)
Restores a previously saved sessions folder into the container at startup.
*   **Enable**: Set `ENABLE_SESSION_RESTORE` to `true`.
*   **Source**: Provide the download URL via `SESSION_RESTORE_URL_ONE`, `_TWO`, or `_THREE` in GitHub Secrets.
    *   **Fallback**: You can also edit the script file and set `HARDCODED_RESTORE_URL`.
*   **Smart Logic**: The script downloads the zip and searches for *any* `.zip` file inside it to handle variable naming, then extracts the nested `sessions` folder.
*   **Mounting**: The folder is mounted to `/usr/src/microsoft-rewards-script/dist/browser/sessions`.

### 3. Robust Build System
*   **Phase 1**: Standard `docker build`.
*   **Phase 2**: Fallback with increased timeouts, pre-pulled base images, and BuildKit optimizations.

## Configuration

You can configure the behavior using Environment Variables in the Workflow files.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `PROJECT_NAME` | Identifier for the current workflow (e.g., `007-of-one`). | Set in YAML |
| `ENABLE_SESSION_UPLOAD`| Master toggle for extraction feature. | `true` |
| `ENABLE_ARTIFACT_UPLOAD`| Upload zip to GitHub Actions Artifacts. | `true` |
| `ENABLE_RELEASE_UPLOAD`| Upload zip to GitHub Release (`project-007`). | `false` |
| `ENABLE_SESSION_RESTORE`| Enable downloading/mounting old sessions. | `false` |
| `SESSION_RESTORE_URL_...`| URL to download sessions (ONE, TWO, or THREE). | `""` |
| `ARTIFACT_NAME_CUSTOM` | Custom name for the uploaded zip. | `""` |
| `SESSION_COPY_DELAY` | Time (seconds) to wait before copying sessions. | `2400` (40m) |
| `MIN_SLEEP_MINUTES` | Passed to container. | `1` |
| `MAX_SLEEP_MINUTES` | Passed to container. | `2` |

## How to Run

### Locally
```bash
# Enable upload, wait 60 seconds
export ENABLE_SESSION_UPLOAD=true
export SESSION_COPY_DELAY=60
./one.sh
```

### GitHub Actions
1.  Go to the "Actions" tab.
2.  Select the desired workflow.
3.  Click "Run workflow".
4.  **Artifacts**: Check the "Artifacts" section of the run summary.
5.  **Releases**: Check the "Releases" page for tag `project-007`.
