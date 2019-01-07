# Create a configuration for restoring via INTERNAL/infix-backup

# Create our own locale, used only for infix-backup restore.
mkdir -p $ROOTFS_DIR/usr/lib/locale
localedef -f UTF-8 -i en_US $ROOTFS_DIR/usr/lib/locale/C.UTF-8
StopIfError "Could not create locale"
