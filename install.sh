#!/usr/bin/env bash
INSTALL_PATH="/opt/docker-volume-backup"

version()
{
  echo "1.0.0"
}

isInstalled()
{
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

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

if [ "$#" -ne 0 ]; then
    echo -e "Illegal parameters."
    exit
fi

ls ${INSTALL_PATH} &> /dev/null
if [ "$?" = "0" ];then
    echo "Program already installed."
    exit
fi

cp $(realpath $0 | grep .*volumes-docker-backup -o) ${INSTALL_PATH} -R
#git clone https://github.com/ocariot/volumes-docker-backup ${INSTALL_PATH} > /dev/null
#git -C ${INSTALL_PATH} checkout "tags/$(version)" > /dev/null

ln -s ${INSTALL_PATH}/volume.sh /usr/local/bin/volume
chmod +x /usr/local/bin/volume

STATUS=$(isInstalled)
if ${STATUS}; then
    echo "****OCARIoT Project was installed with success!****"
else
    echo "OCARIoT Project wasn't installed with success!"
fi