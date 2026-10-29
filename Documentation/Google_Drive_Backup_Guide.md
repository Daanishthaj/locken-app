# Google Drive Backup Guide

Kissa Focus includes an optional, secure Google Drive integration that backs up your project and notes to a folder named exactly `COPY of KISSA FOCUS`.

## Setup

1. Open Kissa Focus.
2. Navigate to **Settings -> Integrations**.
3. Under **Google Drive Backup**, click **Connect**.
4. Complete the OAuth flow in your browser.

## Safe Code Backup Rules

The backup system is designed to **never** upload sensitive data.

It explicitly excludes:
- API keys, Notion tokens, Google OAuth tokens.
- macOS Keychain data.
- `.env` files and local credential files (e.g., `Configuration.plist`).
- DerivedData, Build products, `.DS_Store`.
- User-private databases and usage history.

### The `.backupignore` File

This project includes a `.backupignore` file. It functions similarly to `.gitignore` but includes stricter rules specifically for the Google Drive upload.

### Secret Scanner

Before any upload, the `BackupManager` runs a `SecretScanner` across all queued files. It checks for common secret patterns (OpenAI keys, bearer tokens, etc.). If a potential secret is found, the file is automatically excluded from the backup, and a warning is generated in the `backup_manifest.json`.

## Backup Modes

- **Manual Backup**: Triggered by clicking "Back Up Project Now".
- *(Future)* **Versioned Snapshot**: Saves to a timestamped subfolder.
- *(Future)* **Incremental Sync**: Automatically syncs safe changed files.
