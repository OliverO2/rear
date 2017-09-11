has_binary system-backup
StopIfError "Could not find system-backup script"

pyinstaller --log-level WARN --specpath build --distpath build/dist --onefile --strip "$(which system-backup)"
StopIfError "PyInstaller could not bundle system-backup binary"

COPY_AS_IS=( "${COPY_AS_IS[@]}" '/etc/opt/system-backup/*' )
PROGS=( "${PROGS[@]}" 'build/dist/system-backup' )

# Create our own locale, used only for system-backup restore.
mkdir -p $ROOTFS_DIR/usr/lib/locale
localedef -f UTF-8 -i en_US $ROOTFS_DIR/usr/lib/locale/C.UTF-8
StopIfError "Could not create locale"
