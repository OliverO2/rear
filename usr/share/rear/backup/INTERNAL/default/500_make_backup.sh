# Create a backup via INTERNAL/system-backup

[[ -n "$INTERNAL_BACKUP_TARGET_CONFIGURATION" ]] || Error "Configuration variable INTERNAL_BACKUP_TARGET_CONFIGURATION not set"
[[ -n "$INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION" ]] || Error "Configuration variable INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION not set"
[[ -n "$INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION" ]] || Error "Configuration variable INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION not set"
[[ -n "$INTERNAL_BACKUP_LOG_FILE" ]] || Error "Configuration variable INTERNAL_BACKUP_LOG_FILE not set"

LogUserOutput "Creating system backup"

LC_ALL=C.UTF-8 system-backup "${INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION[@]}" --log_file "$INTERNAL_BACKUP_LOG_FILE" backup create --progress_file "/var/log/system-backup.status" --cleanup --configuration "$INTERNAL_BACKUP_TARGET_CONFIGURATION" --repository "$INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION"

StopIfError "Failed to create backup - see $INTERNAL_BACKUP_LOG_FILE for details."

LogUserOutput "Successfully created system backup"
