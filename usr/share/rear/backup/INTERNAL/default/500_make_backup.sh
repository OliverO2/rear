# Create a backup via INTERNAL/infix-backup

LogUserOutput "Creating system backup"

systemctl start infix-backup.service

StopIfError "Failed to create backup - run 'systemctl status infix-backup.service' for details."

LogUserOutput "Successfully created system backup"
