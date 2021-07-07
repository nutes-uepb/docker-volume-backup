#!/usr/bin/env bash
#
# volume.sh - Backup and restore Docker volumes.
#
# Email:      lucas.barbosa@nutes.uepb.edu.br
# Author:      Lucas Barbosa Oliveira
# Maintenance: Lucas Barbosa Oliveira
#
# ------------------------------------------------------------------------------------------------------------------- #
#  This program will backup and restore Docker volumes.
#
#  Examples:
#      To configure the environment variables, use the following interface:
#      $ volume edit-config
#      To perform a backup generation, the following interface is reserved:
#      $ volume backup <volumes-name>
#      To restore a volume, the following interface is reserved:
#      $ volume restore <volumes-name>
# ------------------------------------------------------------------------------------------------------------------- #
# Historic:
#
#   v1.0.0 25/11/2020, Lucas Barbosa:
#				 - backup/restore locally;
#        - backup/restore in the cloud (Google Drive/AWS S3);
#        - backup schedule;
#        - keeping backups in cache;
#        - command availability: volume uninstall and volume version;
#   v1.1.0 13/10/2020, Lucas Barbosa:
#        - Code optimization;
#   v1.1.1 13/10/2020, Lucas Barbosa:
#        - Correcting the README;
#        - Adding the help operation;
#        - Setting the image version of the volumerize;
#   v1.1.2 13/10/2020, Lucas Barbosa:
#        - Correcting the execution times of the hook scripts;
# ------------------------------------------------------------------------------------------------------------------- #
# Tested in:
#   bash 4.4.20
#   Docker Engine 18.06.0+
# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- FUNCTIONS ----------------------------------------- #

print_message() {
	echo -e "$2$1"
}

close_program() {
	local color="${GREEN}"
	[ "$2" ] && [ $2 -ne 0 ] && color="${RED}"
	[ -n "$1" ] && print_message "$1" "${color}"
	[ "${color}" = "${RED}" ] && exit 1 || exit 0
}

check_env_config() {
	# Verifying the existence of .env
	[ -f "${INSTALL_PATH}/.env" ] || cp ${INSTALL_PATH}/.env.example ${INSTALL_PATH}/.env
}

edit_env_config() {
	editor ${INSTALL_PATH}/.env
	set -a && . ${INSTALL_PATH}/.env && set +a
}

validate_env_environment() {
	[ -z "$(echo $1 | grep -P "$2")" ] && close_program "$3"  1
}

cloud_bkps() {
	docker run -t $1 --rm --name ${CONTAINER_NAME} \
		-v ${GOOGLE_CREDENTIALS_VOLUME}:/credentials \
		-e "VOLUMERIZE_SOURCE=/source" \
		-e "VOLUMERIZE_TARGET=${CLOUD_TARGET}" \
		-e "GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY}" \
		-e "AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID}" \
		-e "AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY}" \
		blacklabelops/volumerize:"${VOLUMERIZE_VERSION}" "${@:2}"

	[ $? -ne 0 ] && close_program "There was a problem communicating with the cloud service" 1
}

check_target_restore_config() {
	local error_message="The CLOUD_TARGET variable does not correspond to the RESTORE_TARGET variable."

	case ${RESTORE_TARGET} in
		LOCAL)
			[ -z "${LOCAL_TARGET}" ] && close_program "The LOCAL_TARGET environment variable have not been defined." 1
			;;
		GOOGLE_DRIVE)
			[ -z "${CLOUD_TARGET}" ] && close_program "The CLOUD_TARGET environment variable have not been defined." 1
			validate_env_environment ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${error_message}"
			;;
		AWS)
			[ -z "${CLOUD_TARGET}" ] && close_program "The CLOUD_TARGET environment variable have not been defined." 1
			validate_env_environment ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${error_message}"
			;;
		*)
			close_program "The value ${RESTORE_TARGET} in RESTORE_TARGET variable is not supported." 1
			;;
	esac
}

check_target_config() {
	[ -z "${CLOUD_TARGET}" ] && [ -z "${LOCAL_TARGET}" ] && close_program "No target defined." 1

	local error_message="The value in CLOUD_TARGET variable is invalid."

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^gdocs")" ]; then
		validate_env_environment ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${error_message}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			close_program "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined." 1
		fi
		local creds_file_name="googledrive.cred"
		local creds_file="$(cloud_bkps "" find /credentials -name ${creds_file_name})"
		if [ -z "$(echo ${creds_file} | grep ${creds_file_name})" ]; then
			cloud_bkps "-i" list
		fi
	fi

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^s3")" ]; then
		validate_env_environment ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${error_message}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			close_program "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined." 1
		fi
	fi
}

multi_backup_config() {
	cat > "$1" << EOF
[
]
EOF

	[ "${LOCAL_TARGET}" ] && {
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >> $1
	}

	[ "${CLOUD_TARGET}" ] && {
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >> $1
	}

}

restore_config() {
	cat > "$1" << EOF
[
]
EOF

	sed -i 's/]//g;s/}$/},/g' $1

	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >> $1
	else
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >> $1
	fi
}

check_crontab() {
	[ -n "$(crontab -u "${USER}" -l | grep -F "$1")" ] && echo "enable" || echo "disable"
}

scheduling() {
	local status=$(check_crontab "$1")
	[ "${status}" = "enable" ] && {
		crontab -u ${USER} -l
		close_program "Backup is already scheduled"
	}
	(
		crontab -u ${USER} -l
		echo "$1 >/dev/null 2>&1"
	) | crontab -u ${USER} -

	status=$(check_crontab "$1")

	if [ "${status}" = "enable" ]; then
		crontab -u ${USER} -l && close_program "Backup schedule successful!"
	else
		close_program "Unsuccessful backup schedule!" 1
	fi
}

check_volume_in_docker() {
	# Checking if volume exist
	local volume_name=$(docker volume ls --format {{.Name}} | grep -E "^$1$")
	[ -z "${volume_name}" ] && close_program "Volume ${volume_name} not found." 1
}

check_volume_in_fs() {
	# Checking if volume exist
	[ "${RESTORE_TARGET}" = "LOCAL" ] && {
		[ -d "${LOCAL_TARGET}" ] || close_program "Directory ${LOCAL_TARGET} not found." 1
		[ -d "${LOCAL_TARGET}/$1" ] || close_program "Volume backup $1 weren't found." 1
	}
}

check_volume_in_cloud() {
	# Checking if volume exist
	[ "${RESTORE_TARGET}" != "LOCAL" ] && {
		local expression_grep=$(echo "$1" | sed 's/ /|/g')
		local cloud_volumes=$(cloud_bkps "" list --verbosity=9 | grep -oE "${expression_grep}" | sort -u)
		[ -z "${cloud_volumes}" ] && close_program "No volume backup was found." 1
	}
}

execute_scripts() {
	[ -d "$1" ] && {
		local scripts=$(ls $1/*.sh)
		for script in ${scripts}; do
			source ${script}
		done
	}
}

# ------------------------------------------------------------------------------------------------------------------- #

INSTALL_PATH="${HOME}/.docker-volume-backup"

# ------------------------------- TESTS ----------------------------------------- #

[ "$(docker ps --format {{.Names}} | grep -e "^${CONTAINER_NAME}$")" ] && {
	close_program "Backup or restore operation in progress. Try again at the end of this operation." 1
}

check_env_config

# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- VARIABLES ----------------------------------------- #

source ${INSTALL_PATH}/.env
VOLUMERIZE_VERSION="1.5.1"
GREEN="\033[32m"
RED="\033[31m"
BOLD="\033[1m"
CONTAINER_NAME="${CONTAINER_NAME:-backup-container}"
GOOGLE_CREDENTIALS_VOLUME="${GOOGLE_CREDENTIALS_VOLUME:-google-drive-credentials}"
TZ="${TZ:-Brazil/East}"
OPERATION=""
VOLUMES=""

USAGE="
USAGE:
 volume - [ACTIONS]
          edit-config - To configure the environment variables.
          backup -To perform a backup generation.
          restore - To restore a volume.
          version - Command used to view the current version of the installed software.
          uninstall - Interface used to uninstall the program.

        - [OPTIONS]
         --time - You can restore from a particular backup by adding a time parameter to the command restore.
         --pre - Directory path that contains the scripts that will be executed before starting the backup or restore operation.
         --pos - Directory path containing the scripts that will be executed after starting the backup or restore operation.
         --remove-cache - Parameter used to remove the cache volume used during the restore operation.
         --expression -  Parameter used to define a crontab expression that will schedule the generation of a backup. The value of this option must be passed in double quotes.
"

# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- EXECUTIONS ----------------------------------------- #

case "$1" in
		backup | restore | edit-config | version | uninstall | help) OPERATION="$1" && shift;;
		*) print_message "${USAGE}" "${BOLD}" && close_program "Invalid operation." 1
esac

while test -n "$1"
do
	case "$1" in
			--pre) CLI_PRE_SCRIPTS_PATH="$2" && shift ;;
			--pos) CLI_POS_SCRIPTS_PATH="$2" && shift ;;
			--timer) TIME="$2" && shift ;;
			--expression) EXPRESSION="$2" && shift ;;
			--remove-cache) REMOVE_CACHE="true" ;;
			*) [ -z "$(echo "$1" | grep -e "^--")" ] && VOLUMES="$1 ${VOLUMES}" ;;
	esac
	shift
done

case "${OPERATION}" in
	backup)
		# checking target variables
		check_target_config

		# setting operation and configuring volume property
		COMMAND="backupFull"
		BACKUP_VOLUME_PROPERTY=""
		SOURCE_VOLUME_PROPERTY="ro"

		[ -n "${EXPRESSION}" ] && {
			COMMAND_SCHEDULE="$0 ${OPERATION} ${VOLUMES}"
			[ -n "${CLI_PRE_SCRIPTS_PATH}" ] && COMMAND_SCHEDULE="${COMMAND_SCHEDULE} --pre ${CLI_PRE_SCRIPTS_PATH}"
			[ -n "${CLI_POS_SCRIPTS_PATH}" ] && COMMAND_SCHEDULE="${COMMAND_SCHEDULE} --pos ${CLI_POS_SCRIPTS_PATH}"
			[ -n "${REMOVE_CACHE}" ] && COMMAND_SCHEDULE="${COMMAND_SCHEDULE} --remove-cache"
			scheduling "${EXPRESSION} ${COMMAND_SCHEDULE}"
		}

		execute_scripts "${PRE_STRATEGIES}"; execute_scripts "${CLI_PRE_SCRIPTS_PATH}"
		for VOLUME in ${VOLUMES}; do
			# Checking if volume exist
			check_volume_in_docker "${VOLUME}"
		done
		;;
	restore)
		execute_scripts "${PRE_STRATEGIES}"; execute_scripts "${CLI_PRE_SCRIPTS_PATH}"
		# checking target variables
		check_target_config
		# checking restore variables
		check_target_restore_config

		# setting operation and configuring volume property
		COMMAND="restore"
		BACKUP_VOLUME_PROPERTY="ro"
		SOURCE_VOLUME_PROPERTY=""

		[ "${TIME}" ] && COMMAND="${COMMAND} --time ${TIME}"

		for VOLUME in ${VOLUMES}; do
			# Checking if volume exist
			check_volume_in_fs "${VOLUME}"
			check_volume_in_cloud "${VOLUME}"
		done

		for VOLUME in ${VOLUMES}; do
			[ "$(docker volume ls --format {{.Name}}| grep -we "^${VOLUME}$")" ] && {
				docker volume rm ${VOLUME} > /dev/null
				[ $? -eq 0 ] && echo "Volume ${VOLUME} removed." || close_program "Restore failed to remove the volume." 1
			}
		done
		;;
	edit-config)
		check_env_config && edit_env_config && close_program
		;;
	version)
		print_message "Version: $(git -C ${INSTALL_PATH} describe --tags --abbrev=0)" "${GREEN}" && close_program
		;;
	help)
		print_message "${USAGE}" "${BOLD}" && close_program
		;;
	uninstall)
		sed -i "/PATH=\$PATH:.*.docker-volume-backup$/d" ${HOME}/.bashrc && rm -Rf "${INSTALL_PATH}"
		if [ ! -d "${INSTALL_PATH}" ]; then
			print_message "****Docker Volume Backup Project was uninstalled with success!****" "${GREEN}"
		else
			print_message "Docker Volume Backup Project wasn't uninstalled with success!" "${RED}"
		fi
		close_program
		;;
esac

# Createing target file that will be used
BKP_CONFIG_MODEL=$(mktemp --suffix=.json)

for VOLUME in ${VOLUMES}; do

	if [ "${OPERATION}" = "backup" ]; then
		# Creating target file for backup
		multi_backup_config "${BKP_CONFIG_MODEL}" "${VOLUME}"
	else
		# Creating target file for restore backup
		restore_config "${BKP_CONFIG_MODEL}" "${VOLUME}"
	fi

	CACHE_VOLUME="cache-${VOLUME}"

	docker run -t --rm \
		--name ${CONTAINER_NAME} \
		-v "${BKP_CONFIG_MODEL}":/etc/volumerize/multiconfig.json:rw \
		-v ${GOOGLE_CREDENTIALS_VOLUME}:/credentials \
		-v "${LOCAL_TARGET}":/local-backup:${BACKUP_VOLUME_PROPERTY} \
		-v "${VOLUME}":/source:${SOURCE_VOLUME_PROPERTY} \
		-v ${CACHE_VOLUME}:/volumerize-cache \
		-e GOOGLE_DRIVE_ID=${CLOUD_ACCESS_KEY_ID} \
		-e GOOGLE_DRIVE_SECRET=${CLOUD_SECRET_ACCESS_KEY} \
		-e AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID} \
		-e AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY} \
		-e VOLUMERIZE_SOURCE="/source" \
		-e VOLUMERIZE_TARGET="multi:///etc/volumerize/multiconfig.json?mode=mirror&onfail=abort" \
		-e TZ=${TZ} \
		blacklabelops/volumerize:"${VOLUMERIZE_VERSION}" bash -c "${COMMAND} && remove-older-than ${BACKUP_DATA_RETENTION} --force"

	[ "${REMOVE_CACHE}" ] && {
		docker volume rm ${CACHE_VOLUME} > /dev/null
		if [ $? -ne 0 ]; then
			print_message "Cache volume ${CACHE_VOLUME} failed when tried removed." "${GREEN}"
		else
			print_message "Cache volume ${CACHE_VOLUME} removed with success." "${RED}"
		fi
	}
done

# removing taget file
rm -f "${BKP_CONFIG_MODEL}"

execute_scripts "${POS_STRATEGIES}"; execute_scripts "${CLI_POS_SCRIPTS_PATH}"

# ------------------------------------------------------------------------------------------------------------------- #
