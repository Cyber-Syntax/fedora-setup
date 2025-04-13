# Bash Coding Rules

- Use lowercase for internal variables (unless they're constants)
- Use `#!/usr/bin/env bash` as the shebang line.
- Always add conventional comments.
- Use double quotes around variables (e.g., "$var") unless you specifically need word splitting or globbing.
- Use logging statements to record key actions and errors.
- If possible, store configurable variables in a separate configuration file rather than hardcoding them in the script.
- Always check return codes of commands in scripts.
- Use descriptive error messages.
- Keep functions focused on a single task.
- Use local variables within functions.