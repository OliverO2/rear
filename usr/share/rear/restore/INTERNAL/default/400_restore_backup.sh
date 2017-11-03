# Restore a backup via INTERNAL/system-backup

[[ -n "$INTERNAL_BACKUP_TARGET_CONFIGURATION" ]] || Error "Configuration variable INTERNAL_BACKUP_TARGET_CONFIGURATION not set"
[[ -n "$INTERNAL_BACKUP_NETWORK_REPOSITORY_HOST" ]] || Error "Configuration variable INTERNAL_BACKUP_NETWORK_REPOSITORY_HOST not set"
[[ -n "$INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION" ]] || Error "Configuration variable INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION not set"
[[ -n "$INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION" ]] || Error "Configuration variable INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION not set"
[[ -n "$INTERNAL_BACKUP_DISK_REPOSITORY_LOCATION" ]] || Error "Configuration variable INTERNAL_BACKUP_DISK_REPOSITORY_LOCATION not set"

disk_mount_directory="/mnt/backup"

#
# Discover repositories and let the user choose one
#
while true; do
    # Discover available repositories (network plus external USB disks)
    repository_locations=("Network $INTERNAL_BACKUP_NETWORK_REPOSITORY_HOST")
    for device in /dev/sd*1; do
        if [[ -b "$device" ]]; then
            device_info=$(
                udevadm info -a "$device" | awk -v device="$device" '
                    BEGIN {
                        usb = 0;
                    }
                    /SUBSYSTEMS=="usb"/ {
                        usb = 1;
                    }
                    usb && /ATTRS{manufacturer}/ {
                        sub("^.*ATTRS{manufacturer}==\"", "");
                        sub(" *\"$", "");
                        manufacturer = $0;
                    }
                    usb && /ATTRS{product}/ {
                        sub("^.*ATTRS{product}==\"", "");
                        sub(" *\"$", "");
                        product = $0;
                    }
                    usb && product > "" && /looking at parent device / {
                        exit;
                    }
                    END {
                        if (manufacturer > "" || product > "") {
                            printf("Disk %s (%s %s)\n", device, manufacturer, product);
                        }
                    }
                '
            )
            if [[ -n "$device_info" ]]; then
                repository_locations=("${repository_locations[@]}" "$device_info")
            fi
        fi
    done

    LogUserOutput "
Please choose a repository location to restore from
(or Plug in a USB drive and press Enter):

$(printf '%s\n' "${repository_locations[@]}" | cat -n)
"

    repository_choice="$(UserInput -I RESTORE_INTERNAL_SELECT_REPOSITORY -t 0 -p "Enter a choice")"

    case "$repository_choice" in
        ([1-9])
            if [[ "$repository_choice" -le "${#repository_locations[@]}" ]]; then
                repository_location="${repository_locations[repository_choice-1]}"
                break
            else
                UserOutput "Choice $repository_choice is larger than the number of repository locations"
            fi
            ;;

        (*)
            UserOutput "Choice $repository_choice is not a number"
            ;;
    esac
done


#
# Prepare the chosen repository for access
#
case "$repository_location" in
    "Network "*)
        repository="$INTERNAL_BACKUP_NETWORK_REPOSITORY_LOCATION"
        remote_user_option=("${INTERNAL_BACKUP_NETWORK_REMOTE_USER_OPTION[@]}")

        LogUserOutput "Repository located at $repository"
        ;;

    "Disk "*)
        read -r -a repository_location_components <<< "$repository_location"
        device="${repository_location_components[1]}"

        repository="$disk_mount_directory$INTERNAL_BACKUP_DISK_REPOSITORY_LOCATION"
        remote_user_option=()

        while ! cryptsetup --readonly open --type luks "$device" backup; do
            LogUserOutput "Could not decrypt disk partition $device"
            sleep 1
        done
        AddExitTask cryptsetup close backup

        [[ -d "$disk_mount_directory" ]] || mkdir "$disk_mount_directory"

        /bin/mount -t ext4 -o ro /dev/mapper/backup "$disk_mount_directory"
        StopIfError "Could not mount encrypted repository partition"
        AddExitTask umount "$disk_mount_directory"

        LogUserOutput "Repository located on disk partition $device at $INTERNAL_BACKUP_DISK_REPOSITORY_LOCATION"
        ;;
esac


#
# Discover available sources
#

available_sources=($(LC_ALL=C.UTF-8 system-backup --quiet list-sources --configuration "$INTERNAL_BACKUP_TARGET_CONFIGURATION" --filter backup))
StopIfError "Could not discover configured backup sources"


#
# Display available backups
#
available_backups="$(LC_ALL=C.UTF-8 system-backup --quiet "${remote_user_option[@]}" backup list \
    --repository "$repository" --sources "${available_sources[0]}" | tail -3 | sed 's;/[^/]*$;;')"
StopIfError "Could not find available backups in repository $repository"
LogUserOutput "
Last 3 backups available in the repository $repository:

$available_backups

About to restore from the last backup.

"


#
# Let the user choose which sources to restore
#
while true; do
    LogUserOutput "Please choose one or more sources to restore:

$(printf '%s\n' "${available_sources[@]}" | cat -n)
"

    selected_sources=()
    choice_input="$(UserInput -I RESTORE_INTERNAL_SELECT_SOURCES -t 0 -p "Enter comma-separated values, or leave empty for all")"

    IFS=',' read -r -a choices <<< "$choice_input"

    for repository_choice in "${choices[@]}"; do
        case "$repository_choice" in
            ([1-9])
                if [ "$repository_choice" -le "${#available_sources[@]}" ]; then
                    selected_source="${available_sources[repository_choice-1]}"
                    selected_sources=("${selected_sources[@]}" "$selected_source")
                else
                    UserOutput "Choice $repository_choice is larger than the number of sources"
                    continue 2
                fi
                ;;
            (*)
                UserOutput "Choice $repository_choice is not a number"
                continue 2
                ;;
        esac
    done

    break
done


#
# Restore chosen sources from the backup
#
LogUserOutput "
Recovering from backup in repository $repository"
if [ ${#selected_sources[@]} -eq 0 ]; then
    LogUserOutput "Restoring all sources"
    source_options=()
else
    LogUserOutput "Restoring sources ${selected_sources[*]}"
    source_options=("--sources" "${selected_sources[@]}")
fi
LC_ALL=C.UTF-8 system-backup "${remote_user_option[@]}" restore-recent --complete_existing_directories \
    --repository "$repository" --configuration "$INTERNAL_BACKUP_TARGET_CONFIGURATION" "${source_options[@]}" -- "$TARGET_FS_ROOT"
StopIfError "Could not successfully finish system-backup restore"


#
# Make snapshots for just-restored sources where possible
#
restored_snapshot_sources=($(LC_ALL=C.UTF-8 system-backup --quiet list-sources \
    --configuration "$INTERNAL_BACKUP_TARGET_CONFIGURATION" "${source_options[@]}" --filter snapshot+backup))
restore_date_time="$(date --iso-8601=s)"
for restored_snapshot_source in "${restored_snapshot_sources[@]}"; do
    subvolume="$TARGET_FS_ROOT$restored_snapshot_source"
    snapshot="$subvolume-$restore_date_time-restore"
    if [[ -d "$TARGET_FS_ROOT$restored_snapshot_source" ]]; then
        LogUserOutput "Creating snapshot $snapshot"
        btrfs subvolume snapshot "$subvolume" "$snapshot"
    fi
done


#
# Offer the user an opportunity to examine and act upon restoration results
#
LogUserOutput "
Please check the restored backup in the provided shell and, when finished, type exit
in the shell to continue recovery."

rear_shell "Did the backup properly restore to $TARGET_FS_ROOT? Are you ready to continue recovery? "

LogUserOutput "
system-backup restore finished successfully"
