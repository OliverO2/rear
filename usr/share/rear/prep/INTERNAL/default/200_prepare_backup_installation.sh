# Configure the INTERNAL/infix-backup installation

has_binary infix-backup || Error "Could not find infix-backup script"

local work_directory="$TMP_DIR/infix-backup.pyinstaller"
mkdir -p "$work_directory" || Error "Could not create $work_directory"

# Compile the infix-backup into a single executable
(cd "$work_directory" && pyinstaller --log-level WARN --onefile --paths /usr/share/infix-backup --exclude-module _pytest --exclude-module coverage --exclude-module coverage.cmdline --strip "$(which infix-backup)")
StopIfError "PyInstaller could not bundle infix-backup binary"

# Copy infix-backup, support programs, and configuration
PROGS=( "${PROGS[@]}" "$work_directory/dist/infix-backup" )
COPY_AS_IS=( "${COPY_AS_IS[@]}" /etc/infix-backup )
