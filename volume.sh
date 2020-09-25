#!/usr/bin/env bash
INSTALL_PATH="${HOME}/.docker-volume-backup"

check_env_config() {
	# Verifying the existence of .env
	if [ ! $(find ${INSTALL_PATH} -name .env) ]; then
		cp ${INSTALL_PATH}/.env.example ${INSTALL_PATH}/.env
	fi
}

edit_env_config() {
	editor ${INSTALL_PATH}/.env
	set -a && . ${INSTALL_PATH}/.env && set +a
}

validate_env_environment() {
	if [ -z "$(echo $1 | grep -P "$2")" ]; then
		echo "$3"
		exit
	fi
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
		blacklabelops/volumerize "${@:2}"

	if [ $? -ne 0 ]; then
		echo "There was a problem communicating with the cloud service"
		exit
	fi
}

check_target_restore_config() {
	ERROR_MESSAGE="The CLOUD_TARGET variable does not correspond to the RESTORE_TARGET variable."

	case ${RESTORE_TARGET} in
		LOCAL)
			if [ -z "${LOCAL_TARGET}" ]; then
				echo "The LOCAL_TARGET environment variable have not been defined."
				exit 1
			fi
			;;
		GOOGLE_DRIVE)
			if [ -z "${CLOUD_TARGET}" ]; then
				echo "The CLOUD_TARGET environment variable have not been defined."
				exit 1
			fi
			validate_env_environment ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${ERROR_MESSAGE}"
			;;
		AWS)
			if [ -z "${CLOUD_TARGET}" ]; then
				echo "The CLOUD_TARGET environment variable have not been defined."
				exit 1
			fi
			validate_env_environment ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
			;;
		*)
			echo "The value ${RESTORE_TARGET} in RESTORE_TARGET variable is not supported."
			exit 1
			;;
	esac
}

check_target_config() {
	if [ -z "${CLOUD_TARGET}" ] && [ -z "${LOCAL_TARGET}" ]; then
		echo "No target defined."
		exit 1
	fi

	ERROR_MESSAGE="The value in CLOUD_TARGET variable is invalid."

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^gdocs")" ]; then
		validate_env_environment ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit 1
		fi
		CREDS_FILE_NAME="googledrive.cred"
		CREDS_FILE="$(cloud_bkps "" find /credentials -name ${CREDS_FILE_NAME})"
		if [ -z "$(echo ${CREDS_FILE} | grep ${CREDS_FILE_NAME})" ]; then
			cloud_bkps "-i" list
		fi
	fi

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^s3")" ]; then
		validate_env_environment ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit 1
		fi
	fi
}

multi_backup_config() {
	cat > "$1" << EOF
[
]
EOF

	if [ "${LOCAL_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >> $1
	fi

	if [ "${CLOUD_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >> $1
	fi

}

restore_config() {
	cat > "$1" << EOF
[
]
EOF

	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >> $1
	else
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >> $1
	fi
}

check_crontab() {
	RET_CRONTAB_COMMAND=$(crontab -u "${USER}" -l | grep -F "$1")

	if [ "${RET_CRONTAB_COMMAND}" ]; then
		echo "enable"
	else
		echo "disable"
	fi
}

scheduling() {
	STATUS=$(check_crontab "$1")
	if [ "${STATUS}" = "enable" ]; then
		crontab -u ${USER} -l
		echo "Backup is already scheduled"
		exit
	fi
	(
		crontab -u ${USER} -l
		echo "$1 >/dev/null 2>&1"
	) | crontab -u ${USER} -

	STATUS=$(check_crontab "$1")

	if [ "${STATUS}" = "enable" ]; then
		crontab -u ${USER} -l
		echo "Backup schedule successful!"
		exit
	else
		echo "Unsuccessful backup schedule!"
		exit 1
	fi
}

check_volume_in_docker() {
	# Checking if volume exist
	VOLUME_NAME=$(docker volume ls --format {{.Name}} | grep -E "^$1$")
	if [ -z "${VOLUME_NAME}" ]; then
		echo "Volume ${VOLUME_NAME} not found."
		exit 1
	fi
}

check_volume_in_fs() {
	# Checking if volume exist
	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		DIRECTORIES=$(ls ${LOCAL_TARGET} 2> /dev/null)
		if [ $? -ne 0 ]; then
			echo "Directory ${LOCAL_TARGET} not found."
			exit 1
		fi

		if [ -z "$(echo "${DIRECTORIES}" | grep -w "$1")" ]; then
			echo "No volume backup was found."
			exit 1
		fi
	fi
}

check_volume_in_cloud() {
	# Checking if volume exist
	if [ "${RESTORE_TARGET}" != "LOCAL" ]; then
		EXPRESSION_GREP=$(echo "$1" | sed 's/ /|/g')
		CLOUD_VOLUMES=$(cloud_bkps "" list --verbosity=9 \
			                                          | grep -oE "${EXPRESSION_GREP}" | sort -u)

		if [ -z "${CLOUD_VOLUMES}" ]; then
			echo "No volume backup was found."
			exit 1
		fi
	fi
}

execute_scripts() {
	if [ "$(ls $1 2> /dev/null)" ]; then
		SCRIPTS=$(ls $1/*.sh)
		for SCRIPT in ${SCRIPTS}; do
			source ${SCRIPT}
		done
	fi
}

get_parameter() {
	PARAMETER_VALUE=""
	PARAMETER=$(($(echo "${@:2}" | sed 's/ /\n/g' | grep -ne "$1" | cut -f1 -d:) + 2))
	if [ ${PARAMETER} -ne 2 ]; then
			PARAMETER_VALUE="${@:${PARAMETER}:1}"
	fi
	echo "${PARAMETER_VALUE}"
}

get_volumes() {
	CRONTAB_EXPRESSION="\(\(\(\([0-9]\+,\)\+[0-9]\+\|\([0-9]\+\(/\|-\)[0-9]\+\)\|[0-9]\+\|*\) \?\)\{4\}\)"
	PARAMETER_INDEX=$(echo ${@:2} | sed 's/ /\n/g' | grep -ne "--" | cut -f1 -d:)
	VALUE_INDEX=$(echo ${PARAMETER_INDEX} | sed 's/ /\n/g' | awk '$1!=""{print $1+1}')
	if [ "${PARAMETER_INDEX}" ]; then
		echo "${@:2}" | cut -f"${PARAMETER_INDEX} ${VALUE_INDEX}" -d" " --complement | sed "s@${CRONTAB_EXPRESSION}@@g"
	else
		echo "${@:2}"
	fi
}

exist_parameter() {
	PARAMETER=$(echo "${@:2}" | grep -we "$1")
	if [ "${PARAMETER}" ]; then
		echo "true"
	else
		echo "false"
	fi
}

if [ "$(docker ps --format {{.Names}} | grep -e "^${CONTAINER_NAME}$")" ]; then
	echo "Backup or restore operation in progress. Try again at the end of this operation."
	exit 1
fi

check_env_config
source ${INSTALL_PATH}/.env

CONTAINER_NAME="${CONTAINER_NAME:-backup-container}"
GOOGLE_CREDENTIALS_VOLUME="${GOOGLE_CREDENTIALS_VOLUME:-google-drive-credentials}"
TZ="${TZ:-Brazil/East}"

CLI_PRE_SCRIPTS_PATH=$(get_parameter "--pre" $@)

# Checking operation
if [ "$1" = "backup" ]; then
	# checking target variables
	check_target_config

	# setting operation and configuring volume property
	COMMAND="backupFull"
	BACKUP_VOLUME_PROPERTY=""
	SOURCE_VOLUME_PROPERTY="ro"

	VOLUMES=$(get_volumes "$@")
	COLUMN_EXPRESSION=$(echo "$@" | sed 's/ /\n/g' | grep -ne "--expression" | cut -f1 -d:)
	if [ "${COLUMN_EXPRESSION}" ]; then
		COMMAND_SCHEDULE="${@:0:${COLUMN_EXPRESSION}} ${@:$((${COLUMN_EXPRESSION}+2))}"
		EXPRESSION="${@:$((${COLUMN_EXPRESSION}+1)):1}"
		scheduling "${EXPRESSION} ${COMMAND_SCHEDULE}"
	fi

	if [ "${CLI_PRE_SCRIPTS_PATH}" ];then
		execute_scripts ${CLI_PRE_SCRIPTS_PATH}
	fi

	if [ "${PRE_STRATEGIES}" ]; then
		execute_scripts ${PRE_STRATEGIES}
	fi

	for VOLUME in ${VOLUMES}; do
		# Checking if volume exist
		check_volume_in_docker "${VOLUME}"
	done

elif [ "$1" = "restore" ]; then
	if [ "${CLI_PRE_SCRIPTS_PATH}" ];then
		execute_scripts ${CLI_PRE_SCRIPTS_PATH}
	fi

	if [ "${PRE_STRATEGIES}" ]; then
		execute_scripts ${PRE_STRATEGIES}
	fi

	# checking target variables
	check_target_config
	# checking restore variables
	check_target_restore_config

	# setting operation and configuring volume property
	COMMAND="restore"
	BACKUP_VOLUME_PROPERTY="ro"
	SOURCE_VOLUME_PROPERTY=""

	TIME=$(get_parameter "--time" $@)
	VOLUMES=$(get_volumes "$@")

	if [ "${TIME}" ]; then
		COMMAND="${COMMAND} --time ${TIME}"
	fi

	for VOLUME in ${VOLUMES}; do
		# Checking if volume exist
		check_volume_in_fs "${VOLUME}"
		check_volume_in_cloud "${VOLUME}"
	done

	for VOLUME in ${VOLUMES}; do
		if [ "$(docker volume ls --format {{.Name}}| grep -we "^${VOLUME}$")" ]; then
			docker volume rm ${VOLUME} > /dev/null
			if [ $? -ne 0 ]; then
				echo "Restore failed to remove the volume."
				exit 1
			fi
			echo "Volume ${VOLUME} removed."
		fi
	done
elif [ "$1" = "edit-config" ]; then
	check_env_config
	edit_env_config
	exit
elif [ "$1" = "version" ]; then
	echo "Version: $(git -C ${INSTALL_PATH} describe --tags --abbrev=0)"
	exit
elif [ "$1" = "uninstall" ]; then
	sed -i "/alias volume=/d" ${HOME}/.bashrc
	rm -Rf "${INSTALL_PATH}"
	ls ${INSTALL_PATH} &> /dev/null
	if [ "$?" != "0" ]; then
		echo "****Docker Volume Backup Project was uninstalled with success!****"
	else
		echo "Docker Volume Backup Project wasn't uninstalled with success!"
	fi
	exec bash
	exit
else
	echo "Invalid operation."
	exit 1
fi

# Createing target file that will be used
BKP_CONFIG_MODEL=$(mktemp --suffix=.json)

for VOLUME in ${VOLUMES}; do
	if [ "$1" = "backup" ]; then
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
		-e GOOGLE_DRIVE_ID="${CLOUD_ACCESS_KEY_ID}" \
		-e GOOGLE_DRIVE_SECRET="${CLOUD_SECRET_ACCESS_KEY}" \
		-e AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID} \
		-e AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY} \
		-e VOLUMERIZE_SOURCE="/source" \
		-e VOLUMERIZE_TARGET="multi:///etc/volumerize/multiconfig.json?mode=mirror&onfail=abort" \
		-e TZ=${TZ} \
		blacklabelops/volumerize bash -c "${COMMAND} && remove-older-than ${BACKUP_DATA_RETENTION} --force"

	REMOVE_CACHE=$(exist_parameter "/" $@)

	if ${REMOVE_CACHE}; then
		docker volume rm ${CACHE_VOLUME} > /dev/null
		if [ $? -ne 0 ]; then
			echo "Cache volume ${CACHE_VOLUME} failed when tried removed."
		else
			echo "Cache volume ${CACHE_VOLUME} removed with success."
		fi
	fi
done

# removing taget file
rm -f "${BKP_CONFIG_MODEL}"

CLI_POS_SCRIPTS_PATH=$(get_parameter "--pos" $@)
if [ "${CLI_POS_SCRIPTS_PATH}" ];then
	execute_scripts ${CLI_POS_SCRIPTS_PATH}
fi

if [ "${POS_STRATEGIES}" ]; then
	execute_scripts ${POS_STRATEGIES}
fi
