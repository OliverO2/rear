host_name="$(uname -n)"
log_file="/var/log/system-backup/backup.log"

LogUserOutput "Creating system-backup archive for $host_name"

LC_ALL=C.UTF-8 system-backup --remote_user "root" --log_file "$log_file" backup create --progress_file "/var/log/system-backup.status" --cleanup "/etc/opt/system-backup/$host_name"

StopIfError "Failed to create backup - see $log_file for details."

LogUserOutput "Successfully created system-backup archive for $host_name"
