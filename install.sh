#!/usr/bin/env bash
#
# install.sh - Script to perform the installation of the program.
#
# Email:      lucas.barbosa@nutes.uepb.edu.br
# Author:      Lucas Barbosa Oliveira
# Maintenance: Lucas Barbosa Oliveira
# ------------------------------------------------------------------------------------------------------------------- #
#  This script will perform the installation of the volume backup and restore program.
#
#  Example:
#      To install run the following commands:
#      $ ./install.sh | source ${HOME}/.bashrc
# ------------------------------------------------------------------------------------------------------------------- #
# Historic:
#
#   v1.0.0 25/11/2020, Lucas Barbosa:
#				 - creation of the installation script;
#   v1.1.0 13/10/2020, Lucas Barbosa:
#				 - removing the ʻexec bash` command after installation;
#				 - Changing the version;
#   v1.1.1 13/10/2020, Lucas Barbosa:
#				 - Changing the version;
#				 - Code optimization;
#   v1.1.2 13/10/2020, Lucas Barbosa:
#				 - Changing the version;
#   v1.1.3 07/07/2021, Lucas Barbosa:
#				 - Changing installation local of volume application;
# ------------------------------------------------------------------------------------------------------------------- #
# Tested in:
#   bash 4.4.20
# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- FUNCTIONS ----------------------------------------- #
version()
{
  echo "1.1.3"
}

# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- VARIABLES ----------------------------------------- #

INSTALL_PATH="${HOME}/.docker-volume-backup"
GREEN="\033[32m"
RED="\033[31m"

# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- TESTS ----------------------------------------- #

[ "$#" -ne 0 ] && echo -e "Illegal parameters." && exit 1
[ -d "${INSTALL_PATH}" ] && echo "Program already installed." && exit 0

# ------------------------------------------------------------------------------------------------------------------- #

# ------------------------------- EXECUTIONS ----------------------------------------- #

git clone https://github.com/nutes-uepb/docker-volume-backup ${INSTALL_PATH} > /dev/null
git -C ${INSTALL_PATH} checkout "tags/$(version)" > /dev/null

chmod +x ${INSTALL_PATH}/volume.sh
mv ${INSTALL_PATH}/volume.sh ${INSTALL_PATH}/volume
echo "PATH=\$PATH:${INSTALL_PATH}" >> ${HOME}/.bashrc

if [ -d "${INSTALL_PATH}" ];then
    echo -e "${GREEN}****Docker Volume Backup Project was installed with success!****"
else
    echo -e "${RED}Docker Volume Backup Project wasn't installed with success!"
    exit 1
fi

# ------------------------------------------------------------------------------------------------------------------- #
