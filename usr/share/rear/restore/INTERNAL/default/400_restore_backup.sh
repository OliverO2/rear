# Restore a backup via INTERNAL/infix-backup

disk_mount_directory="/mnt/backup/"

#
# Discover repositories and let the user choose one
#
while true; do
    # Discover available repositories (network plus external USB disks)
    repository_locations=("Default")
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

    choice_input="$(UserInput -I RESTORE_INTERNAL_SELECT_REPOSITORY -t 0 -p "Enter a choice")"

    if [[ "$choice_input" =~ ^[1-9][0-9]*$ ]]; then
        if [[ "$choice_input" -le "${#repository_locations[@]}" ]]; then
            repository_location="${repository_locations[choice_input-1]}"
            break
        else
            UserOutput "Choice $choice_input is larger than the number of repository locations"
        fi
    else
        [[ -n "$choice_input" ]] && UserOutput "Choice '$choice_input' is not a positive number"
    fi
done


#
# Prepare the chosen repository for access
#
case "$repository_location" in
    "Default")
        repository_options=()
        LogUserOutput "Using default repository"
        ;;

    "Disk "*)
        read -r -a repository_location_components <<< "$repository_location"
        device="${repository_location_components[1]}"

        repository_directory="$disk_mount_directory/$(basename "$INTERNAL_BACKUP_REPOSITORY_DIRECTORY")"
        repository_options=("--repository_directory" "$repository_directory")

        while ! cryptsetup --readonly open --type luks "$device" backup; do
            LogUserOutput "Could not decrypt disk partition $device"
            sleep 1
        done
        AddExitTask cryptsetup close backup

        [[ -d "$disk_mount_directory" ]] || mkdir "$disk_mount_directory"

        /bin/mount -t ext4 -o ro /dev/mapper/backup "$disk_mount_directory"
        StopIfError "Could not mount encrypted repository partition"
        AddExitTask umount "$disk_mount_directory"

        LogUserOutput "Repository located on disk partition $device at $repository_directory"
        ;;
esac


#
# Display available backup sets
#
available_backup_set_limit=10
IFS=$'\n' GLOBIGNORE='*' available_backup_sets=($(LC_ALL=C.UTF-8 infix-backup --quiet "${repository_options[@]}" backup list --sets --limit $available_backup_set_limit))
StopIfError "Could not find available backups in the repository"
unset IFS GLOBIGNORE


#
# Let the user choose which backup set to restore from
#
while true; do
    LogUserOutput "
Please choose the backup set to restore from. These are the recent
$available_backup_set_limit backup sets available in the repository:

$(printf '%s\n' "${available_backup_sets[@]}" | cat -n)
"

    choice_input="$(UserInput -I RESTORE_INTERNAL_SELECT_BACKUP_SET -t 0 -p "Enter a choice")"

    if [[ "$choice_input" =~ ^[1-9][0-9]*$ ]]; then
        if [[ "$choice_input" -le "${#available_backup_sets[@]}" ]]; then
            selected_backup_set="$(sed 's; -- .*$;;' <<< "${available_backup_sets[choice_input-1]}")"
            break
        else
            UserOutput "Choice $choice_input is larger than the number of available backup sets"
        fi
    else
        UserOutput "Choice '$choice_input' is not a positive number"
    fi
done


#
# Discover available sources
#

IFS=$'\n' GLOBIGNORE='*' available_sources=($(LC_ALL=C.UTF-8 infix-backup --source_root "$TARGET_FS_ROOT" --quiet list-sources --filter backup))
StopIfError "Could not discover configured backup sources"
unset IFS GLOBIGNORE


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
    unset IFS

    for choice in "${choices[@]}"; do
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]]; then
            if [[ "$choice" -le "${#available_sources[@]}" ]]; then
                selected_source="$(sed 's;^'"$TARGET_FS_ROOT"';;' <<< "${available_sources[choice-1]}")"
                selected_sources=("${selected_sources[@]}" "$selected_source")
            else
                UserOutput "Choice $choice is larger than the number of sources"
                continue 2
            fi
        else
            UserOutput "Choice '$choice' is not a positive number"
            continue 2
        fi
    done

    break
done


#
# Restore chosen sources from the backup
#
LogUserOutput "
Recovering from backup '$selected_backup_set'"
if [[ ${#selected_sources[@]} -eq 0 ]]; then
    LogUserOutput "Restoring all sources"
    source_options=()
else
    LogUserOutput "Restoring sources ${selected_sources[*]}"
    source_options=("--sources" "${selected_sources[@]}" "--end_of_list")
fi
LC_ALL=C.UTF-8 infix-backup "${repository_options[@]}" \
    restore-recent --complete_existing_directories "${source_options[@]}" -d "$selected_backup_set" "$TARGET_FS_ROOT"
StopIfError "Could not successfully finish infix-backup restore"


#
# Make snapshots for just-restored sources where possible
#
LC_ALL=C.UTF-8 infix-backup --source_root "$TARGET_FS_ROOT" snapshot create


#
# Offer the user an opportunity to examine and act upon restoration results
#
LogUserOutput "
Please check the restored backup in the provided shell and, when finished, type exit
in the shell to continue recovery."

rear_shell "Did the backup properly restore to $TARGET_FS_ROOT? Are you ready to continue recovery? "

LogUserOutput "
infix-backup restore finished successfully"
