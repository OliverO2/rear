# Configure the INTERNAL/system-backup installation

has_binary system-backup || Error "Could not find system-backup script"

[[ -n "$INTERNAL_BACKUP_TARGET_CONFIGURATION" ]] || Error "Configuration variable INTERNAL_BACKUP_TARGET_CONFIGURATION not set"

local work_directory="$TMP_DIR/system-backup.pyinstaller"
mkdir -p "$work_directory" || Error "Could not create $work_directory"

# Compile the system-backup into a single executable
(cd "$work_directory" && pyinstaller --log-level WARN --onefile --exclude-module _pytest --exclude-module coverage --exclude-module coverage.cmdline --strip "$(which system-backup)")
StopIfError "PyInstaller could not bundle system-backup binary"

# Copy system-backup, support programs, and configuration
PROGS=( "${PROGS[@]}" "$work_directory/dist/system-backup" )
COPY_AS_IS=( "${COPY_AS_IS[@]}" "$INTERNAL_BACKUP_TARGET_CONFIGURATION" )
