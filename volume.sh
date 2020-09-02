#!/usr/bin/env bash
INSTALL_PATH="${HOME}/.docker-volume-backup"

check_config() {
  # Verifying the existence of .env
  if [ ! $(find ${INSTALL_PATH} -name .env) ]
  then
    cp ${INSTALL_PATH}/.env.example ${INSTALL_PATH}/.env
  fi
}

edit_config() {
  editor ${INSTALL_PATH}/.env
  set -a && . ${INSTALL_PATH}/.env && set +a
}

validate_env_environment() {
	if [ -z "$(echo $1 | grep -P "$2")" ]; then
		echo "$3"
		exit
	fi
}

check_restore_target_config() {
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
		validate_env_environment ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "CLOUD_TARGET" "${ERROR_MESSAGE}"
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

check_backup_target_config() {
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
#		CREDS_FILE_NAME="googledrive.cred"
#		CREDS_FILE="$(cloud_bkps "" $1 $2 find /credentials -name ${CREDS_FILE_NAME})"
#		if [ -z "$(echo ${CREDS_FILE} | grep ${CREDS_FILE_NAME})" ]; then
#			cloud_bkps "-i" $1 $2 list
#		fi
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
	cat >"$1" <<EOF
[
]
EOF

	if [ "${LOCAL_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >>$1
	fi

	if [ "${CLOUD_TARGET}" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >>$1
	fi

}

restore_config() {
	cat >"$1" <<EOF
[
]
EOF

	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"file:///local-backup/$2\" }\n]" >>$1
	else
		sed -i 's/]//g;s/}$/},/g' $1
		echo -e " { \"description\": \"Local disk test\", \"url\": \"${CLOUD_TARGET}/$2\" }\n]" >>$1
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
    (crontab -u ${USER} -l; echo "$1") | crontab -u ${USER} -

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

check_config
source ${INSTALL_PATH}/.env

# Createing target file that will be used
BKP_CONFIG_MODEL=$(mktemp --suffix=.json)

# Checking operation
if [ "$1" = "backup" ];then
  # checking backup variables
  check_backup_target_config

  # setting operation and configuring volume property
  COMMAND="backupFull"
  BACKUP_VOLUME_PROPERTY=""
  SOURCE_VOLUME_PROPERTY="ro"

  # Checking if volume exist
  VOLUME_NAME=$(docker volume ls --format {{.Name}} | grep -E "^$2$")
  if [ -z "${VOLUME_NAME}" ]; then
    echo "Volume not found."
    exit 1
  fi

  COLUMN_EXPRESSION=$(($(echo "$@" | sed 's/ /\n/g' | grep -ne "--expression" | cut -f1 -d:) + 1))
  EXPRESSION="${@:${COLUMN_EXPRESSION}:1}"
  COMMAND_SCHEDULE=$(echo "${@:0}" | sed "s@ --expression\( \([0-9]\|*\)\)\{5\}@@g")
  if [ ${COLUMN_EXPRESSION} -ne 1 ]; then
    scheduling "${EXPRESSION} ${COMMAND_SCHEDULE}"
  fi

  # Creating target file for backup
  multi_backup_config "${BKP_CONFIG_MODEL}" "${VOLUME_NAME}"

elif [ "$1" = "restore" ];then
  # checking restore variables
  check_restore_target_config

  # setting operation and configuring volume property
	COMMAND="restore"
	BACKUP_VOLUME_PROPERTY="ro"
	SOURCE_VOLUME_PROPERTY=""

	# Checking if volume exist
	if [ "${RESTORE_TARGET}" = "LOCAL" ]; then
		DIRECTORIES=$(ls ${LOCAL_TARGET} 2>/dev/null)
        if [ $? -ne 0 ]; then
          echo "Directory ${LOCAL_TARGET} not found."
          exit 1
        fi

        if [ -z "$(echo "${DIRECTORIES}" | grep -w "$2")" ]; then
          echo "No volume backup was found."
          exit 1
        fi
	fi

	# Creating target file for restore backup
	restore_config "${BKP_CONFIG_MODEL}" "${VOLUME_NAME}"
elif [ "$1" = "edit-config" ];then
    check_config
    edit_config
    exit
elif [ "$1" = "version" ];then
    echo "Version: $(git -C ${INSTALL_PATH} describe --tags --abbrev=0)"
    exit
elif [ "$1" = "uninstall" ];then
    sed -i "/alias volume=/d" ${HOME}/.bashrc
    rm -Rf "${INSTALL_PATH}"
    ls ${INSTALL_PATH} &> /dev/null
    if [ "$?" = "0" ];then
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

if [ "$(docker ps --format {{.Names}} | grep -e "^volumerize$")" ]; then
    echo "Backup or restore operation in progress. Try again at the end of this operation."
    exit 1
fi

docker run -ti --rm \
    --name volumerize \
    -v "${BKP_CONFIG_MODEL}":/etc/volumerize/multiconfig.json:rw \
    -v google-credentials:/credentials \
    -v "${LOCAL_TARGET}":/local-backup${BACKUP_VOLUME_PROPERTY} \
    -v "${VOLUME_NAME}":/source:${SOURCE_VOLUME_PROPERTY} \
    -v cache_volume:/volumerize-cache \
    -e GOOGLE_DRIVE_ID="${CLOUD_ACCESS_KEY_ID}" \
	-e GOOGLE_DRIVE_SECRET="${CLOUD_SECRET_ACCESS_KEY}" \
	-e AWS_ACCESS_KEY_ID=${CLOUD_ACCESS_KEY_ID} \
	-e AWS_SECRET_ACCESS_KEY=${CLOUD_SECRET_ACCESS_KEY} \
    -e VOLUMERIZE_SOURCE="/source" \
    -e VOLUMERIZE_TARGET="multi:///etc/volumerize/multiconfig.json?mode=mirror&onfail=abort" \
    blacklabelops/volumerize bash -c "${COMMAND} && remove-older-than ${BACKUP_DATA_RETENTION} --force"

# removing taget file
rm -f "${BKP_CONFIG_MODEL}"
