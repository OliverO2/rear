#
# opaladmin-workflow.sh
#

WORKFLOW_opaladmin_DESCRIPTION="administrate TCG Opal 2-compatible disks"
WORKFLOWS+=( opaladmin )

function opaladmin_usage_error() {
    # prints usage information, then exits.

    Error "Use '$PROGRAM opaladmin -- --help' for more information."
}

function opaladmin_help() {
    # prints a help message.

    LogPrintError "Usage: '$PROGRAM opaladmin -- [OPTIONS]'"
    LogPrintError "  Administrate TCG Opal 2-compatible disks"
    LogPrintError ""
    LogPrintError "Valid options:"
    LogPrintError "  -h, --help                   print this help message and exit"
    LogPrintError "  --setup                      enable locking on available disk(s) and assign a device password"
    LogPrintError "  --changePW                   change the device password on available disk(s)"
    LogPrintError "  --updatePBA                  update the PBA image on disk(s) whose shadow MBR is enabled"
    LogPrintError "  --unlock                     unlock available disk(s)"
    LogPrintError "  --resetDEK=DEVICE            assign a new data encryption key, ERASING ALL DATA ON THE DISK"
    LogPrintError "  --factoryRESET=DEVICE        reset the device to factory defaults, ERASING ALL DATA ON THE DISK"
    LogPrintError "  -i FILE, --image=FILE        use FILE as the PBA image (default: ${OPALPBA_URL:-none}, if local)"
    LogPrintError "  -d DEVICE, --device=DEVICE   perform operations on DEVICE only"
    LogPrintError ""
    LogPrintError "If multiple Opal 2-compliant disks are available and DEVICE is not specified, operations are"
    LogPrintError "performed on each such disk, except for PBA image installation, which is only performed on disks"
    LogPrintError "designated as boot disks for disk unlocking (on those disks the shadow MBR has been enabled)."
}

function WORKFLOW_opaladmin() {
    # ReaR command 'opaladmin'

    [[ -n "$DEBUGSCRIPTS" ]] && set -$DEBUGSCRIPTS_ARGUMENT

    local actions=()
    local device

    Log "Command line options of the opaladmin workflow: $*"

    # Parse options
    local options="$(getopt -n "$PROGRAM opaladmin" -o "hi:d:" -l "help,setup,changePW,updatePBA,unlock,resetDEK:,factoryRESET:,image:,device:" -- "$@" 2>&8)"
    [[ $? != 0 ]] && opaladmin_usage_error

    eval set -- "$options"
    while true; do
        case "$1" in
            (-h|--help)
                opaladmin_help
                return 0
                ;;
            (--setup)
                actions+=( "setup" "resetDEK" )
                shift
                ;;
            (--changePW)
                actions+=( "changePW" )
                shift
                ;;
            (--updatePBA)
                actions+=( "updatePBA" )
                shift
                ;;
            (--unlock)
                actions+=( "unlock" )
                shift
                ;;
            (--resetDEK)
                actions+=( "resetDEK" )
                device="$2"
                shift 2
                ;;
            (--factoryRESET)
                actions+=( "factoryRESET" )
                device="$2"
                shift 2
                ;;
            (-i|--image)
                opaladmin_image_file="$2"
                shift 2
                ;;
            (-d|--device)
                device="$2"
                shift 2
                ;;
            (--)
                shift
                break
                ;;
            (*)
                Error "Internal error during option processing (\"$1\")"
                ;;
        esac
    done

    if ((${#actions[@]} < 1)); then
        PrintError "No action has been requested on the command line."
        opaladmin_usage_error
    fi

    # Find TCG Opal 2-compliant disks
    opaladmin_devices=( $(opal_devices) )
    (( ${#opaladmin_devices[@]} == 0 )) && Error "Could not detect TCG Opal-compliant disks."

    if [[ -n "$device" ]]; then
        if IsInArray "$device" "${opaladmin_devices[@]}"; then
            opaladmin_devices=( "$device" )
        else
            Error "Device \"$device\" could not be identified as being an Opal 2-compliant disk"
        fi
    fi

    for action in "${actions[@]}"; do
        LogPrint "Executing action \"opaladmin_$action\""
        eval "opaladmin_$action"
    done

    return 0
}

function opaladmin_setup() {
    # enables locking on available disk(s) and assigns a device password.

    local device
    local -i device_number=1

    for device in "${opaladmin_devices[@]}"; do
        LogUserOutput "Setting up Opal locking on device \"$device\" ($(opal_device_identification "$device"))..."
        opaladmin_get_password
        opal_device_setup "$device" "$opaladmin_password"
        StopIfError "Could not set up device \"$device\"."
        LogUserOutput "Setup successful."

        local prompt="Shall device \"$device\" act as a boot device for disk unlocking (y/n)? "
        confirmation="$(opaladmin_choice_input "OPALADMIN_SETUP_BOOT_$device_number" "$prompt" "y" "n")"

        if [[ "$confirmation" == "y" ]]; then
            opaladmin_get_image_file
            LogUserOutput "Enabling and uploading the PBA on device \"$device\", please wait..."
            opal_device_enable_mbr "$device" "$opaladmin_password"
            StopIfError "Could not enable the MBR on device \"$device\"."
            opal_device_load_pba_image "$device" "$opaladmin_password" "$opaladmin_image_file"
            StopIfError "Could not upload the PBA image to device \"$device\"."
            LogUserOutput "PBA enabled and uploaded."
        fi

        device_number+=1
    done
}

function opaladmin_changePW() {
    # changes the device password on available disk(s).

    local new_password device try_count

    while true; do
        new_password="$(opaladmin_password_input "OPALADMIN_NEW_PASSWORD" "Enter new disk password: ")"
        local new_password_repeated="$(opaladmin_password_input "OPALADMIN_NEW_PASSWORD" "Repeat new disk password: ")"

        [[ "$new_password_repeated" == "$new_password" ]] && break

        PrintError "New passwords do not match."
    done

    for device in "${opaladmin_devices[@]}"; do
        LogUserOutput "Changing disk password of device \"$device\" ($(opal_device_identification "$device"))..."
        for try_count in $(seq 3); do
            opaladmin_get_password "old password"
            if opal_device_change_password "$device" "$opaladmin_password" "$new_password"; then
                LogUserOutput "Password changed."
                break 2
            else
                opaladmin_password=""  # Assume that the password for this disk did not fit, retry with a new one
                PrintError "Could not change password."
            fi
        done
        PrintError "Changing disk password of device \"$device\" unsuccessful."
    done

    opaladmin_password="$new_password"
}

function opaladmin_updatePBA() {
    # updates the PBA image on disk(s) whose shadow MBR is enabled.

    local device

    for device in "${opaladmin_devices[@]}"; do
        if opal_device_mbr_is_enabled "$device"; then
            opaladmin_get_image_file
            LogUserOutput "Updating the PBA on device \"$device\" ($(opal_device_identification "$device")), please wait..."
            opaladmin_get_password
            opal_device_load_pba_image "$device" "$opaladmin_password" "$opaladmin_image_file"
            StopIfError "Could not upload the PBA image to device \"$device\"."
            LogUserOutput "PBA updated."
        fi
    done
}

function opaladmin_unlock() {
    # unlocks available disk(s).

    local device

    opaladmin_get_password

    for device in "${opaladmin_devices[@]}"; do
        LogUserOutput "Unlocking device \"$device\" ($(opal_device_identification "$device"))..."
        opal_device_unlock "$device" "$opaladmin_password"
        StopIfError "Could not unlock device \"$device\"."
        LogUserOutput "Device unlocked."
    done
}

function opaladmin_resetDEK() {
    # assigns a new data encryption key, ERASING ALL DATA ON THE DISK.

    local device

    for device in "${opaladmin_devices[@]}"; do
        local confirmation="$(opaladmin_erase_confirmation "$device" "Reset data encryption key (DEK) of device \"$device\"")"

        if [[ "$confirmation" == "YesERASE" ]]; then
            LogUserOutput "About to reset the data encryption key (DEK) of device \"$device\" ($(opal_device_identification "$device"))..."
            opaladmin_get_password
            opal_device_regenerate_dek_ERASING_ALL_DATA "$device" "$opaladmin_password"
            StopIfError "Could not reset data encryption key (DEK) of device \"$device\"."
            LogUserOutput "Data encryption key (DEK) reset, data erased."
        else
            LogUserOutput "Data encryption key (DEK) of device \"$device\" ($(opal_device_identification "$device")) left untouched."
        fi
    done
}

function opaladmin_factoryRESET() {
    # resets the device to factory defaults, ERASING ALL DATA ON THE DISK.

    local device

    for device in "${opaladmin_devices[@]}"; do
        local confirmation="$(opaladmin_erase_confirmation "$device" "Factory-reset device \"$device\"")"

        if [[ "$confirmation" == "YesERASE" ]]; then
            LogUserOutput "About to reset device \"$device\" ($(opal_device_identification "$device")) to factory defaults..."
            opaladmin_get_password
            opal_device_factory_reset_ERASING_ALL_DATA "$device" "$opaladmin_password"
            StopIfError "Could not reset device \"$device\" to factory defaults."
            LogUserOutput "Device reset to factory defaults, data erased."
        else
            LogUserOutput "Device \"$device\" ($(opal_device_identification "$device")) left untouched."
        fi
    done
}

function opaladmin_erase_confirmation() {
    local device="${1:?}"
    local prompt="${2:?}, ERASING ALL DATA (YesERASE/No)? "
    # sets $opaladmin_password, asking the user if not already done.

    local confirmation="No"

    if opal_disk_has_partitions "$device"; then
        if opal_disk_has_mounted_partitions "$device"; then
            LogUserOutput "Device \"$device\" ($(opal_device_identification "$device")) contains mounted partitions:"
            LogUserOutput "$(opal_disk_partition_information "$device")"
        else
            LogUserOutput "Device \"$device\" ($(opal_device_identification "$device")) contains partitions:"
            LogUserOutput "$(opal_disk_partition_information "$device")"
            confirmation="$(opaladmin_choice_input "OPALADMIN_RESETDEK_CONFIRM" "$prompt" "YesERASE" "No")"
        fi
    else
        confirmation="YesERASE"
    fi

    echo "$confirmation"
}

function opaladmin_get_password() {
    local which="${1:-disk password}"
    # sets $opaladmin_password, asking the user if not already done.

    if [[ -z "$opaladmin_password" ]]; then
        opaladmin_password="$(opaladmin_password_input "OPALADMIN_PASSWORD" "Enter $which: ")"
    fi
}

function opaladmin_choice_input() {
    local id="${1:?}"
    local prompt="${2:?}"
    shift 2
    local choices=( "$@" )
    # prints user input after verifying that it complies with one of the choices specified.

    while true; do
        result="$(UserInput -I "$id" -t 0 -p "$prompt")"
        IsInArray "$result" "${choices[@]}" && break
    done

    echo "$result"
}

function opaladmin_password_input() {
    local id="${1:?}"
    local prompt="${2:?}"
    # prints secret user input after verifying that it is non-empty.

    while true; do
        result="$(UserInput -I "$id" -C -r -s -t 0 -p "$prompt")"
        [[ -n "$result" ]] && break
        PrintError "Please enter a non-empty password."
    done

    UserOutput ""
    echo "$result"
}

function opaladmin_get_image_file() {
    # ensures that $opaladmin_image_file is the path of a local image file or exits with an error.

    : ${opaladmin_image_file:="$(opal_local_pba_image_file)"}
    [[ -n "$opaladmin_image_file" ]] || Error "Image file not specified and OPALPBA_URL configuration variable not set - cannot acquire a PBA image"

    opal_check_pba_image "$opaladmin_image_file"
    LogPrint "Using local PBA image file \"$opaladmin_image_file\""
    echo "$opaladmin_image_file"
}