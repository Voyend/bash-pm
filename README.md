# Bash Project Manager (`pm`)

A lightweight project directory manager for bash and Termux. Easily register directory paths and navigate your workspace using `pm open`. It includes built-in bash completion and features for attaching contextual notes, running directory health checks, searching projects, and importing/exporting databases.

## Features
* **Fast Navigation:** Jump to any project directory instantly.
* **Fuzzy Finding:** Interactive search using `fzf` (or native bash `select` fallback).
* **Browser-Style History:** Use `pm back` and `pm forward` to traverse your navigation stack.
* **Zero Dependencies:** Written in pure Bash. Works out of the box.
* **Project Notes:** Attach context, to-dos, or descriptions to your environments.
* **Self-Updating:** Pulls the latest version directly from GitHub.

## Installation
1. Clone the repository to a permanent location:
   ```bash
   git clone [https://github.com/Voyend/bash-pm.git](https://github.com/Voyend/bash-pm.git) ~/projects/bash-pm
   ```
 * Create a symlink to your bash library folder:
   ```bash
   mkdir -p ~/bashlib
   ln -s ~/projects/bash-pm/pm.sh ~/bashlib/pm.sh
   ```
 * Add the following to your ~/.bashrc (or ~/.zshrc):
   ```bash
   source ~/bashlib/pm.sh
   ```
 * Restart your terminal or run `source ~/.bashrc`.

Remote / Single-File Installation
If you don't want to clone the whole repository, you can pull the script directly:
```bash
mkdir -p ~/bashlib
curl -fsSL [https://raw.githubusercontent.com/Voyend/bash-pm/main/pm.sh](https://raw.githubusercontent.com/Voyend/bash-pm/main/pm.sh) -o ~/bashlib/pm.sh
```

Usage
| Command | Description |
|---|---|
| pm add <name> <path> | Register a new project. |
| pm add <name> --current | Register the current directory. |
| pm open | Open the interactive fuzzy finder to select a project. |
| pm open <name> | Navigate immediately to a registered project. |
| pm back / pm forward | Navigate through your project history. |
| pm list | Show all registered projects and paths. |
| pm status | Check which registered paths exist and which are missing. |
| pm note <name> <text> | Add a note to a project. |
| pm upgrade | Fetch and apply the latest version of this script. |
Run pm help for the full list of commands.

Data Storage
Your projects, notes, and history are stored securely as flat files in your home directory (~/.pm_projects, ~/.pm_notes, ~/.pm_history).
