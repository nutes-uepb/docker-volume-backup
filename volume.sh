#!/usr/bin/env bash
INSTALL_PATH="/opt/docker-volume-backup"

isInstalled() {
    ls /usr/local/bin/volume  &> /dev/null
    RET_VOLUME_COMMAND=$?

    ls ${INSTALL_PATH}  &> /dev/null
    RET_PROJECT=$?

    if [ ${RET_VOLUME_COMMAND} = 0 ] &&
      [ ${RET_PROJECT} = 0 ]; then
        echo "true"
        exit
    fi
    echo "false"
}

edit_config()
{
  # Verifying the existence of .env
  if [ ! $(find ${INSTALL_PATH} -name env) ]
  then
    cp ${INSTALL_PATH}/env.example ${INSTALL_PATH}/env
  fi

  editor ${INSTALL_PATH}/$1
  set -a && . ${INSTALL_PATH}/$1 && set +a
}

validate_bkp_target() {
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
			exit
		fi
		;;
	GOOGLE_DRIVE)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "CLOUD_TARGET" "${ERROR_MESSAGE}"
		;;
	AWS)
		if [ -z "${CLOUD_TARGET}" ]; then
			echo "The CLOUD_TARGET environment variable have not been defined."
			exit
		fi
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		;;
	*)
		echo "The value ${RESTORE_TARGET} in RESTORE_TARGET variable is not supported."
		exit
		;;
	esac
}

check_backup_target_config() {
	if [ -z "${CLOUD_TARGET}" ] && [ -z "${LOCAL_TARGET}" ]; then
		echo "No target defined."
		exit
	fi

	ERROR_MESSAGE="The value in CLOUD_TARGET variable is invalid."

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^gdocs")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^gdocs://(.*?)@(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
#		CREDS_FILE_NAME="googledrive.cred"
#		CREDS_FILE="$(cloud_bkps "" $1 $2 find /credentials -name ${CREDS_FILE_NAME})"
#		if [ -z "$(echo ${CREDS_FILE} | grep ${CREDS_FILE_NAME})" ]; then
#			cloud_bkps "-i" $1 $2 list
#		fi
	fi

	if [ "$(echo ${CLOUD_TARGET} | grep -P "^s3")" ]; then
		validate_bkp_target ${CLOUD_TARGET} "^s3://s3..*..amazonaws.com/(.*?).*$" "${ERROR_MESSAGE}"
		if [ -z "${CLOUD_ACCESS_KEY_ID}" ] || [ -z "${CLOUD_SECRET_ACCESS_KEY}" ]; then
			echo "The CLOUD_ACCESS_KEY_ID or CLOUD_SECRET_ACCESS_KEY environment variables have not been defined."
			exit
		fi
	fi

	if [ "${LOCAL_TARGET}" ]; then
		ERROR_MESSAGE="The value in LOCAL_TARGET variable is invalid."
		validate_bkp_target ${LOCAL_TARGET} "^/" "${ERROR_MESSAGE}"
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

source .env

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
    exit
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
          exit
        fi

        if [ -z "$(echo "${DIRECTORIES}" | grep -w "$2")" ]; then
          echo "No volume backup was found."
          exit
        fi
	fi

	# Creating target file for restore backup
	restore_config "${BKP_CONFIG_MODEL}" "${VOLUME_NAME}"
elif [ "$1" = "edit-config" ];then

elif [ "$1" = "version" ];then
    echo "Version: $(git -C ${INSTALL_PATH} describe --tags --abbrev=0)"
    exit
elif [ "$1" = "uninstall" ];then
    rm /usr/local/bin/volume
    rm -R /opt/volumes-docker-backup/
    STATUS=$(isInstalled)
    if ! ${STATUS}; then
        echo "****Volume Docker Backup was uninstalled with success!****"
    else
        echo "Volume Docker Backup wasn't uninstalled with success!"
    fi
    exit
else
    echo "Invalid operation."
    exit
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