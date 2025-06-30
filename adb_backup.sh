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
    declare -a log_file_array
    log_file_array=(\
                    "${log_file}" \
                    "${error_log_file}" \
                   )

    /bin/touch "${log_file_array[@]}"
}

createLogFiles

declare -a command_array
command_array=(\
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
    # needs to be done manually, due to function dependency conflicts.
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
            # TODO: change handling with process substitution, since the processes
            #       inside the process substitution are not waited for.
            {
                echo -e "${date_time_format@P}: \e[01;33m${adb_device_id}: ${message}\e[0m"
            } > >(writeLogFile "error")
            ;;

        "error")
            {
                echo -e "${date_time_format@P}: \e[01;31m${adb_device_id}: ${message}\e[0m"
            } > >(writeLogFile "error")
            ;;

        *)
            {
                # no coloured output
                echo -e "${date_time_format@P}: ${adb_device_id}: ${message}"
            } > >(writeLogFile "error")
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
            outputWarningError "${function_name}: Wrong argument: Must be either 'log' or 'error'." "error"
            kill -s "SIGTERM" "${SCRIPT_PID}"
    esac
}


outputNewline()
{
    {
        echo "${date_time_format@P}:"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
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
    local partition_table
    local partition_name_list

    if [[ -f "${partition_file}" ]]
    then
        # get partition information from file
        partition_table=$(< "${partition_file}")
        # filter list of partition names
        partition_name_list=$(/usr/bin/gawk \
                                --assign="partition_regex=${partition_regex}" \
                                '$0 ~ partition_regex { print $4 }' <<< "${partition_table}" \
                             )
        echo "${partition_name_list}"
    else
        outputWarningError "Could not find file: '${partition_file}'" "error"
        kill -s "SIGTERM" "${SCRIPT_PID}"
    fi
}

executeArchiveCommand()
{
    local image_file="${1}"

    {
        /usr/bin/pixz -9 "${image_file}"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeArchiveVerifyCommand()
{
    declare -a compressed_image_file_array
    compressed_image_file_array=("${@}")

    {
        # terminate each array element by a null-byte character
        printf "%s\0" "${compressed_image_file_array[@]}" \
            | /usr/bin/xargs \
                --null \
                --no-run-if-empty \
                --max-procs="${available_processors}" \
                --max-args="${xargs_max_args}" \
                /usr/bin/xz --test
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeChecksumCommand()
{
    declare -a compressed_image_file_array
    compressed_image_file_array=("${@}")

    {
        # terminate each array element by a null-byte character
        printf "%s\0" "${compressed_image_file_array[@]}" \
            | /usr/bin/xargs \
                --null \
                --no-run-if-empty \
                --max-procs="${available_processors}" \
                --replace="{}" \
                /bin/bash -c \
                    "/usr/bin/b2sum '{}' > '{}.b2'"
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeChecksumVerifyCommand()
{
    declare -a checksum_file_array
    checksum_file_array=("${@}")

    {
        # terminate each array element by a null-byte character
        printf "%s\0" "${checksum_file_array[@]}" \
            | /usr/bin/xargs \
                --null \
                --no-run-if-empty \
                --max-procs="${available_processors}" \
                --max-args="${xargs_max_args}" \
                /usr/bin/b2sum --check --quiet
    } > >(writeLogFile "log") 2> >(writeLogFile "error")
}

executeAdbCommand()
{
    # mandatory
    local device_id="${1}"
    local command_type="${2}"
    local first_parameter="${3}"
    # optional
    local second_parameter="${4}"

    {
        # TODO: exit on error here
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

    local device_pattern="${adb_device_id} +?${boot_mode} ${transport_protocol}.*?${product_name} ${model_name} ${device_name}.*?$"

    if ! /usr/bin/gawk \
        --assign="device_pattern=${device_pattern}" \
        'BEGIN{
            match_found=0;
        }

        {
            adb_command_output=$0;

            if(adb_command_output ~ device_pattern)
                match_found=1;
        }

        END{
            if(match_found)
                # return true
                exit 0;

            else
                # return false
                exit 1;
        }' <<< "${adb_command_output}"
    then
        outputWarningError "The 'ADB device ID' must be: '${adb_device_id}'." "error"
        outputWarningError "The 'transport protocol' must be: '${transport_protocol}'." "error"
        outputWarningError "The 'product name' must be: '${product_name}'." "error"
        outputWarningError "The 'boot mode' must be: '${boot_mode}'." "error"
        outputWarningError "The 'device name' must be: '${device_name}'." "error"
        outputWarningError "The 'model name' must be: '${model_name}'." "error"
        outputWarningError "" "error"
        outputWarningError "ADB command output (\"/usr/bin/adb devices -l\"):" "warning"
        outputWarningError "${adb_command_output}" ""
        outputWarningError "" "error"
        outputWarningError "\e[01;33mMake sure to reboot the device to '${boot_mode} mode', in order to create a clean backup of all partitions: '/usr/bin/adb reboot ${boot_mode}'\e[0m" "warning"
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
    local device_partition_file
    local image_file

    # save partitions as image files
    while read -r partition_name
    do
        device_partition_file="${block_device_directory}/${partition_name}"
        image_file="${backup_directory}/${partition_name}.img"

        outputCurrentStep "Saving block device file: '${device_partition_file}' to '${image_file}'..."
        # "adb pull" is much faster than "adb shell 'cat [...]'"
        executeAdbCommand "${adb_device_id}" "pull" "${device_partition_file}" "${image_file}"
    done <<< "${partition_name_list}"

    outputNewline
}

archiveImages()
{
    local partition_name_list=$(getPartitionList)
    local partition_name
    local image_file
    local compressed_image_file

    while read -r partition_name
    do
        image_file="${backup_directory}/${partition_name}.img"
        compressed_image_file="${image_file}.xz"

        outputCurrentStep "Compressing image file: '${image_file}' to '${compressed_image_file}'..."
        executeArchiveCommand "${image_file}"
    done <<< "${partition_name_list}"

    outputNewline
}

verifyArchiveIntegrity()
{
    local partition_name_list=$(getPartitionList)
    local partition_name
    local image_file
    declare -a compressed_image_file_array

    while read -r partition_name
    do
        image_file="${backup_directory}/${partition_name}.img"
        compressed_image_file_array+=("${image_file}.xz")
    done <<< "${partition_name_list}"

    outputCurrentStep "Verifying archive integrity of: '${compressed_image_file_array[@]}'..."
    executeArchiveVerifyCommand "${compressed_image_file_array[@]}"
    outputNewline
}

generateChecksums()
{
    local partition_name_list=$(getPartitionList)
    local partition_name
    local image_file
    declare -a  compressed_image_file_array
    declare -a checksum_file_array

    while read -r partition_name
    do
        image_file="${backup_directory}/${partition_name}.img"
        compressed_image_file_array+=("${image_file}.xz")
        checksum_file_array+=("${image_file}.xz.b2")
    done <<< "${partition_name_list}"

    outputCurrentStep "Generating BLAKE2 checksum files: '${checksum_file_array[@]}'...\e[0m"
    executeChecksumCommand "${compressed_image_file_array[@]}"
    outputNewline
}

verifyArchiveChecksums()
{
    local partition_name_list=$(getPartitionList)
    local partition_name
    local image_file
    local compressed_image_file
    declare -a checksum_file_array

    while read -r partition_name
    do
        image_file="${backup_directory}/${partition_name}.img"
        compressed_image_file="${image_file}.xz"
        checksum_file_array+=("${compressed_image_file}.b2")
    done <<< "${partition_name_list}"

    outputCurrentStep "Verifying archive checksum using: '${checksum_file_array[@]}'..."
    executeChecksumVerifyCommand "${checksum_file_array[@]}"
}

main()
{
    checkDeviceConnection

    saveSystemInformation

    savePartitionsAsImages

    archiveImages

    # necessary, if the backup is transferred via the network
    verifyArchiveIntegrity

    generateChecksums

    # necessary, if the backup is transferred via the network
    verifyArchiveChecksums
}

main
