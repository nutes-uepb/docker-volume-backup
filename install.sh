#!/usr/bin/env bash
INSTALL_PATH="${HOME}/.docker-volume-backup"

version()
{
  echo "1.0.0"
}

isInstalled()
{
    ls ${INSTALL_PATH}  &> /dev/null
    RET_PROJECT=$?

    if [ ${RET_PROJECT} = 0 ]; then
        echo "true"
        exit
    fi
    echo "false"
}

if [ "$#" -ne 0 ]; then
    echo -e "Illegal parameters."
    exit
fi

ls ${INSTALL_PATH} &> /dev/null
if [ "$?" = "0" ];then
    echo "Program already installed."
    exit
fi
cp "$(realpath $0 | grep .*docker-volume-backup -o)" "${INSTALL_PATH}" -r
#git clone https://github.com/nutes-uepb/docker-volume-backup ${INSTALL_PATH} > /dev/null
#git -C ${INSTALL_PATH} checkout "tags/$(version)" > /dev/null

chmod +x ${INSTALL_PATH}/volume.sh

echo "export PATH=${INSTALL_PATH}:${PATH}" >> ${HOME}/.bashrc
STATUS=$(isInstalled)
if ${STATUS}; then
    echo "****Docker Volume Backup Project was installed with success!****"
else
    echo "Docker Volume Backup Project wasn't installed with success!"
fi