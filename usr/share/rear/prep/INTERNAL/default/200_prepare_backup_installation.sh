# Configure the INTERNAL/system-backup installation

has_binary system-backup || Error "Could not find system-backup script"

[[ -n "$INTERNAL_BACKUP_TARGET_CONFIGURATION" ]] || Error "Configuration variable INTERNAL_BACKUP_TARGET_CONFIGURATION not set"

# Compile the system-backup into a single executable
pyinstaller --log-level WARN --specpath build --distpath build/dist --onefile --strip "$(which system-backup)"
StopIfError "PyInstaller could not bundle system-backup binary"

# Copy system-backup, support programs, and configuration
PROGS=( "${PROGS[@]}" 'build/dist/system-backup' )
COPY_AS_IS=( "${COPY_AS_IS[@]}" "$INTERNAL_BACKUP_TARGET_CONFIGURATION" )
