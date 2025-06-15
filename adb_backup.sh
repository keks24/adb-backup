#!/bin/bash
############################################################################
# Copyright 2025 Ramon Fischer                                             #
#                                                                          #
# Licensed under the Apache License, Version 2.0 (the "License");          #
# you may not use this file except in compliance with the License.         #
# You may obtain a copy of the License at                                  #
#                                                                          #
#     http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                          #
# Unless required by applicable law or agreed to in writing, software      #
# distributed under the License is distributed on an "AS IS" BASIS,        #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. #
# See the License for the specific language governing permissions and      #
# limitations under the License.                                           #
############################################################################

# exit immediately on pipe errors
set -o pipefail

# be able to kill the script gracefully within functions
## on "SIGTERM" signal, execute "exit 1"
trap "exit 1" SIGTERM

# define global variables
script_directory_path="${0%/*}"
script_name="${0##*/}"
# make script pid available for subshells
export SCRIPT_PID="${$}"
configuration_name="${script_name/\.sh/.conf}"
configuration_file="${script_directory_path}/${configuration_name}"
source "${configuration_file}"

# secure access permissions
## created files: 600
## created directories: 700
umask "077"

createBackupDirectories()
{
    /bin/mkdir \
        --parent \
        "${backup_directory}" \
        "${backup_directory}/dev" \
        "${backup_directory}/"{dev/block,etc,proc}
}

createBackupDirectories

createLogFiles()
{
    declare -a file_array
    file_array=(\
                "${log_file}" \
                "${error_log_file}" \
               )
    local file

    for file in "${file_array[@]}"
    do
        /bin/touch "${file}"
        /bin/chmod 600 "${file}"
    done
}

createLogFiles

declare -a command_array
command_array=(\
                "/bin/chmod" \
                "/bin/mkdir" \
                "/bin/touch" \
                "/usr/bin/adb" \
                "/usr/bin/b2sum" \
                "/usr/bin/gawk" \
                "/usr/bin/id" \
                "/usr/bin/nproc" \
                "/usr/bin/pixz" \
                "/usr/bin/tee" \
                "/usr/bin/xargs" \
                "/usr/bin/xz" \
              )
checkCommands()
{
    local current_command

    unalias "${command_array[*]##*/}" 2>/dev/null

    {
        for current_command in "${command_array[@]}"
        do
            if ! command -v "${current_command}" >/dev/null
            then
                echo -e "\e[01;31mCould not find command '${current_command}'.\e[0m" >&2
                kill -s "SIGTERM" "${SCRIPT_PID}"
            fi
        done
    # needs to be done manually, because of dependency conflicts.
    } > >(/usr/bin/tee --append "${log_file}" >&1) 2> >(/usr/bin/tee --append "${error_log_file}" >&2)
}

checkCommands

# define more global variables
## "checkCommands" must be executed before this!
effective_username=$(/usr/bin/id --user --name)
adb_command_output=$(/usr/bin/adb devices -l)
available_processors=$(/usr/bin/nproc --all --ignore="${ignore_processor_count}")

# global functions
outputWarningError()
{
    local message="${1}"
    local message_type="${2}"

    case "${message_type}" in
        "warning")
            echo -e "${date_time_format@P}: \e[01;33m${adb_device_id}: ${message}\e[0m" | /usr/bin/tee --append "${error_log_file}" >&2
            ;;

        "error")
            echo -e "${date_time_format@P}: \e[01;31m${adb_device_id}: ${message}\e[0m" | /usr/bin/tee --append "${error_log_file}" >&2
            ;;

        *)
            # no coloured output
            echo -e "${date_time_format@P}: ${adb_device_id}: ${message}" | /usr/bin/tee --append "${error_log_file}" >&2
            ;;
    esac
}

writeLogFile()
{
    local function_name="${0}"
    local log_type="${1}"

    case "${log_type}" in
        "log")
            if [[ -O "${log_file}" && -r "${log_file}" && -w "${log_file}" ]]
            then
                # redirect to "log file" and to "stdout"
                /usr/bin/tee --append "${log_file}" >&1
            else
                outputWarningError "The log file: '${log_file}' is either not owned by effective user '${effective_username}', has no 'read' or 'write' permissions." "error"
                kill -s "SIGTERM" "${SCRIPT_PID}"
            fi
            ;;

        "error")
            if [[ -O "${log_file}" && -r "${log_file}" && -w "${log_file}" ]]
            then
                # redirect to "error log file" and to "stderr"
                /usr/bin/tee --append "${error_log_file}" >&2
            else
                outputWarningError "The error log file: '${log_file}' is either not owned by effective user '${effective_username}', has no 'read' or 'write' permissions." "error"
                kill -s "SIGTERM" "${SCRIPT_PID}"
            fi
            ;;

        *)
            outputWarningError "${function_name}: Wrong parameter: Must be either 'log' or 'error'." "error"
            kill -s "SIGTERM" "${SCRIPT_PID}"
    esac
}


outputNewline()
{
    echo "${log_date_time_format@P}:" | /usr/bin/tee --append "${log_file}"
}

outputCurrentStep()
{
    local message="${*}"

    {
        echo -e "${date_time_format@P}: \e[01;34m${adb_device_id}: ${message}\e[0m"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

getPartitionList()
{
    local partition_file="${backup_directory}/${partition_table_file}"

    if [[ -f "${partition_file}" ]]
    then
        # get partition information
        local partition_table=$(< "${partition_file}")
        # filter list of partition names
        ## make it globally available
        partition_name_list=$(/usr/bin/gawk \
                                --assign="partition_regex=${partition_regex}" \
                                '$0 ~ partition_regex { print $4 }' <<< "${partition_table}")
        echo "${partition_name_list}"
    else
        outputWarningError "Could not find file: '${partition_file}'" "error"
        kill -s "SIGTERM" "${SCRIPT_PID}"
    fi
}

executeArchiveCommand()
{
    local file="${1}"

    {
        /usr/bin/pixz -9 "${file}"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeArchiveVerifyCommand()
{
    declare -a compressed_file_array
    compressed_file_array=("${@}")
    local compressed_file

    {
        {
            # convert array to null-terminated string
            for compressed_file in "${compressed_file_array[@]}"
            do
                printf "%s\0" "${compressed_file}"
            done
        } | /usr/bin/xargs \
                --null \
                --no-run-if-empty \
                --max-procs="${available_processors}" \
                --max-args="${xargs_max_args}" \
                /usr/bin/xz --test
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeChecksumCommand()
{
    local compressed_file="${1}"
    local checksum_file="${2}"

    {
        /usr/bin/b2sum "${compressed_file}" > "${checksum_file}"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeAdbCommand()
{
    local device_id="${1}"
    local command_type="${2}"
    local first_parameter="${3}"
    local second_parameter="${4}"

    {
        /usr/bin/adb \
            -s "${device_id}" \
            "${command_type}" \
            "${first_parameter}" \
            "${second_parameter}"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

deviceFileDirectoryExists()
{
    local device_file="${1}"

    if executeAdbCommand "${adb_device_id}" "shell" "test -e '${device_file}'" >/dev/null
    then
        # exists
        return 0
    else
        # does not exist
        return 1
    fi
}

checkDeviceConnection()
{
    if ! /usr/bin/gawk \
            --assign="adb_device_id=${adb_device_id}" \
            --assign="transport_protocol=${transport_protocol}" \
            --assign="boot_mode=${boot_mode}" \
            --assign="model_name=${model_name}" \
            --assign="device_name=${device_name}" \
            '{
                adb_command_output=$0
                device_pattern=adb_device_id" +?"boot_mode".?"transport_protocol".?"model_name".*"device_name".*?$"

                if(adb_command_output ~ device_pattern)
                {
                    # return true
                    exit 1
                }
                else
                {
                    # return false
                    exit 0
                }
             }' <<< "${adb_command_output}"
    then
        outputWarningError "The 'ADB device ID' must be: '${adb_device_id}'." "error"
        outputWarningError "The 'transport protocol' must be: '${transport_protocol}'." "error"
        outputWarningError "The 'boot mode' must be: '${boot_mode}'." "error"
        outputWarningError "The 'device name' must be: '${device_name}'." "error"
        outputWarningError "The 'model name' must be: '${model_name}'." "error"
        outputWarningError "" "error"
        outputWarningError "ADB command output (\"/usr/bin/adb devices -l\"):" "warning"
        outputWarningError "${adb_command_output}"
        outputWarningError "" "error"
        outputWarningError "\e[01;33mMake sure to reboot the device to 'recovery mode', in order to create a clean backup of all partitions: \"/usr/bin/adb reboot recovery\"\e[0m" "warning"
        kill -s "SIGTERM" "${SCRIPT_PID}"
    fi
}

saveSystemInformation()
{
    local device_file

    if [[ "${system_information_array[@]}" == *"/proc/partitions"* ]]
    then
        for device_file in "${system_information_array[@]}"
        do
            if deviceFileDirectoryExists "${device_file}"
            then
                outputCurrentStep "Saving file: '${device_file}' to '${backup_directory}/${device_file}'..."
                executeAdbCommand "${adb_device_id}" "pull" "${device_file}" "${backup_directory}/${device_file}"
            else
                outputWarningError "Could not find file on device: '${device_file}'." "error"
                kill -s "SIGTERM" "${SCRIPT_PID}"
            fi
        done
    else
        outputWarningError "Saving the file: '/proc/partitions' is mandatory!" "error"
        kill -s "SIGTERM" "${SCRIPT_PID}"
    fi

    outputCurrentStep "Saving partition labels: from '${partition_label_directory}' to '${partition_label_file}'..."
    if deviceFileDirectoryExists "${partition_label_directory}"
    then
        executeAdbCommand "${adb_device_id}" "shell" "ls -l '${partition_label_directory}'" > "${partition_label_file}"
    else
        outputWarningError "Couldn not find directory on device: '${partition_label_directory}'." "error"
        kill -s "SIGTERM" "${SCRIPT_PID}"
    fi
    outputNewline
}

savePartitionsAsImages()
{
    local partition_name_list=$(getPartitionList)
    local partition_name

    # save partitions as image files
    while read -r partition_name
    do
        local device_partition_file="${block_device_directory}/${partition_name}"
        local image_file="${backup_directory}/${partition_name}.img"

        outputCurrentStep "Saving block device: '${device_partition_file}' to '${image_file}'..."
        # "adb pull" is much faster than "adb shell 'cat [...]'"
        executeAdbCommand "${adb_device_id}" "pull" "${device_partition_file}" "${image_file}"
    done <<< "${partition_name_list}"

    outputNewline
}

archiveImages()
{
    local partition_name_list=$(getPartitionList)
    local partition_name

    while read -r partition_name
    do
        local image_file="${backup_directory}/${partition_name}.img"
        local compressed_image_file="${image_file}.xz"

        outputCurrentStep "Compressing file: '${image_file}' to '${compressed_image_file}'..."
        executeArchiveCommand "${image_file}"
    done <<< "${partition_name_list}"

    outputNewline
}

verifyArchiveIntegrity()
{
    local partition_name_list=$(getPartitionList)
    local partition_name
    declare -a compressed_image_file_array

    while read -r partition_name
    do
        local image_file="${backup_directory}/${partition_name}.img"
        compressed_image_file_array+=("${image_file}.xz")
    done <<< "${partition_name_list}"

    outputCurrentStep "Checking archive integrity of: '${compressed_image_file_array[@]}'..."
    executeArchiveVerifyCommand "${compressed_image_file_array[@]}"
    outputNewline
}

generateChecksums()
{
    local partition_name_list=$(getPartitionList)
    local partition_name

    while read -r partition_name
    do
        local image_file="${backup_directory}/${partition_name}.img"
        local compressed_image_file="${image_file}.xz"
        local checksum_file="${compressed_image_file}.b2"

        outputCurrentStep "Generating BLAKE2 checksum file: '${checksum_file}' of '${image_file}'...\e[0m"
        executeChecksumCommand "${compressed_image_file}" "${checksum_file}"
    done <<< "${partition_name_list}"

    #outputNewline
}

main()
{
    checkDeviceConnection

    saveSystemInformation

    savePartitionsAsImages

    archiveImages

    verifyArchiveIntegrity

    generateChecksums

    # TODO: add function "verifyArchiveChecksums"
    #verifyArchiveChecksums
}

main
