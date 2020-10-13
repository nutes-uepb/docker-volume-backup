#!/usr/bin/env bash
INSTALL_PATH="${HOME}/.docker-volume-backup"

version()
{
  echo "1.1.0"
}

GREEN="\033[32m"
RED="\033[31m"

if [ "$#" -ne 0 ]; then
    echo -e "Illegal parameters."
    exit 1
fi

ls ${INSTALL_PATH} &> /dev/null
if [ "$?" = "0" ];then
    echo "Program already installed."
    exit
fi
git clone https://github.com/nutes-uepb/docker-volume-backup ${INSTALL_PATH} > /dev/null
git -C ${INSTALL_PATH} checkout "tags/$(version)" > /dev/null

chmod +x ${INSTALL_PATH}/volume.sh
echo "alias volume='${INSTALL_PATH}/volume.sh'" >> ${HOME}/.bashrc

if [ -d "${INSTALL_PATH}" ];then
    echo -e "${GREEN}****Docker Volume Backup Project was installed with success!****"
else
    echo -e "${RED}Docker Volume Backup Project wasn't installed with success!"
    exit 1
fi

