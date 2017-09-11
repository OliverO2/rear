Log "Creating system-backup archive for $(uname -n)"

LC_CTYPE=C.UTF-8 system-backup --remote_user "root" --log_file /var/log/system-backup/backup.log backup create --progress_file "/var/log/system-backup.status" --cleanup "/etc/opt/system-backup/$(uname -n)"

StopIfError "Failed to create backup"
