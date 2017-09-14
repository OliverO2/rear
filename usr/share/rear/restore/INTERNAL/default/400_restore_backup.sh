target_hostname="$(uname -n)"
target_configuration="/etc/opt/system-backup/$target_hostname"
sources=( $(awk '/"path": / { sub(/^.*"path": "/, ""); sub(/",.*$/, ""); print; }' "$target_configuration") )
[ ${#sources[@]} -lt 1 ] && Error "Could not discover configured backup sources"


LogUserOutput "
Last 3 backups available in the repository:

$(LC_ALL=C.UTF-8 system-backup --quiet --remote_user root backup list --configuration "$target_configuration" --source "${sources[0]}" | tail -3 | sed 's;/[^/]*$;;')

About to restore from the last backup.

"

while true; do
    LogUserOutput "Please choose one or more from the list of available sources:

$(printf '%s\n' "${sources[@]}" | cat -n)
"

    included_sources=()
    choice_input="$(UserInput -I RESTORE_INTERNAL_SELECT_SOURCES -t 0 -p "Enter comma-separated values, or leave empty for all")"

    IFS=',' read -r -a choices <<< "$choice_input"

    for choice in "${choices[@]}"; do
        case "$choice" in
            ([1-9])
                if [ "$choice" -le "${#sources[@]}" ]; then
                    included_source="${sources[choice-1]}"
                    included_sources=("${included_sources[@]}" "$included_source")
                else
                    UserOutput "Choice $choice is larger than the number of sources"
                    continue 2
                fi
                ;;
            (*)
                UserOutput "Choice $choice is not a number"
                continue 2
                ;;
        esac
    done

    break
done

LogUserOutput "
Recovering from system-backup archive"
if [ ${#included_sources[@]} -eq 0 ]; then
    LogUserOutput "Restoring all sources"
    LC_ALL=C.UTF-8 system-backup --remote_user "root" restore-recent --complete_existing_directories "$target_configuration" "$TARGET_FS_ROOT"
    StopIfError "Could not successfully finish system-backup restore"
else
    for source in "${included_sources[@]}"; do
        LogUserOutput "Restoring source $source"
        LC_ALL=C.UTF-8 system-backup --remote_user "root" restore-recent --complete_existing_directories --source "$source" "$target_configuration" "$TARGET_FS_ROOT"
        StopIfError "Could not successfully finish system-backup restore"
    done
fi

LogUserOutput "
Please check the restored backup in the provided shell and, when finished, type exit
in the shell to continue recovery."

rear_shell "Did the backup properly restore to $TARGET_FS_ROOT? Are you ready to continue recovery? "

LogUserOutput "
system-backup restore finished successfully"
