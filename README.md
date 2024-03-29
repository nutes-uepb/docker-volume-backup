# Docker Volume Backup

## Prerequisites
1. Linux _(Ubuntu 16.04+ recommended)_
2. Docker Engine 18.06.0+
   - Follow all the steps present in the [official documentation](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce).
3. Ensure that the `editor` command is configured with the standard editor used on the terminal. If not, add the editors used. Example, adding the `nano` editor: `sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nano 100`.
    - To choose the default editor use the command: `sudo update-alternatives --config editor`

## Drescription

Project to backup and restore Docker volumes. In addition to performing local backups, you can perform backups on Amazon AWS S3 and Google Driver.

### 1. Instalation
All software installation is performed using the following command:

```sh
curl -o- https://raw.githubusercontent.com/nutes-uepb/docker-volume-backup/1.1.4/install.sh | bash; source ${HOME}/.bashrc
```

```sh
wget -qO- https://raw.githubusercontent.com/nutes-uepb/docker-volume-backup/1.1.4/install.sh | bash; source ${HOME}/.bashrc
```


After the execution of this script has finished, the message `****Docker Volume Backup Project was installed with success!****` will be displayed, thus demonstrating that the software installation was successful. Otherwise, the message to be displayed will be `Docker Volume Backup Project wasn't installed with success!`.

If script execution is successful, the `volume` command will be recognized by bash.

### 2. Set the environment variables

To ensure flexibility and increase security, some parameters are provided via environment variables, eg. `CLOUD_ACCESS_KEY_ID`, `CLOUD_SECRET_ACCESS_KEY`, etc.

To configure the environment variables, use the following interface:

```sh
$ volume edit-config
```
#### 2.1 Data Backup Setup

Variables responsible for defining backup settings. The variables with prefix `CLOUD` are commented out by default, to activate them uncommented and set their respective value based on the values provided by the cloud service that you want to perform the backups and restores. The supported cloud storage services are Google Drive and AWS S3.

In order for backup and restore operations to be successful, credentials must be granted permissions to manipulate the cloud storage location:
    
- [Google Drive](https://console.developers.google.com/apis/credentials)
When performing the first backup, a link will be provided that redirects the browser to a user's authentication screen at Google, thus granting permission to manipulate Google Drive. In future `backup` or `restore` operations, authentication is not required unless the `google-credentials` volume is removed.

- [AWS S3](https://docs.aws.amazon.com/pt_br/sdk-for-java/v1/developer-guide/signup-create-iam-user.html)
To use the `backup` or` restore` operations, it is necessary to associate the following policy with the created user:

```json=
{
    "Version":"2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:ListAllMyBuckets",
            "Resource": "arn:aws:s3:::*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::BUCKET_NAME",
                "arn:aws:s3:::BUCKET_NAME/*"
            ]
        }
    ]
}

```
> :warning: Note: Replace BUCKET_NAME with your bucket name!

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `LOCAL_TARGET` | Defined the path where the generated backup will be stored locally. | `/path/to/backup` |
| `CLOUD_TARGET` | Define a URL and the path where the backup will be stored in the Google Drive or AWS S3 cloud. | `s3://s3.<bucket-region>.amazonaws.com/<bucket-name>[/<path>]` |
| `CLOUD_ACCESS_KEY_ID` | Client Id for access Google Driver or AWS S3 service responsible to store backup data. | `AKIAYXGARMBIICAV23FE` |
| `CLOUD_SECRET_ACCESS_KEY` | Client Secret for access Google Driver or S3 service responsible to store backup data. | `J/YXk2xMaJQugb+vYm+c/TbTz+LpMnkxucdfv/Rh` |
| `RESTORE_TARGET` | Define the target used to restore the backup. example value: `LOCAL, GOOGLE_DRIVE, AWS`. | `AWS` |
| `BACKUP_DATA_RETENTION` | Time the data backup will remain stored. Default value (15 days): `15D`. | `15D` |
| `PRE_STRATEGIES` | Directory path that contains the scripts that will be executed before starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order. | `${HOME}/.docker-volume-backup/strategies/pre` |
| `POS_STRATEGIES` | Directory path containing the scripts that will be executed after starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order. | `${HOME}/.docker-volume-backup/strategies/pos` |
| `TZ` | You can set the time zone with the environment variable TZ. | `Europe/Berlin` |
| `CONTAINER_NAME` | Name of the container that will perform the backup and restore operations. | `backup-container` |
| `GOOGLE_CREDENTIALS_VOLUME` | Volume name that stores the google drive credentials. | `google-drive-credentials` |

### 3. Interface commands

#### 3.1 Backup

To perform a backup generation, the following interface is reserved:

```sh
$ volume backup <volumes-name>
```

To view the volumes available for backup on your machine use the command: `docker volume ls --format {{.Name}}`. To backup multiple volumes, separate them by space, example: `volume backup volume1 volume2`.

:pushpin: Note: Make sure that the volume to be backed up is not in use by any services.

*Optional parameters:*

- `--expression <values>` - Parameter used to define a crontab expression that will schedule the generation of a backup. The value of this option must be passed in double quotes. Example: `volume backup --expression "0 3 * * *"`;
- `--pre <path>` - Directory path that contains the scripts that will be executed before starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order.`;
-  `--pos <path>` - Directory path containing the scripts that will be executed after starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order.;
-  `--remove-cache` - parameter used to remove the cache volume used during the backup operation. The removal of this volume will cause, in the next backup operations, the synchronization of the directory where the backups are being sent. The synchronization will be done before the backup operation is performed. This may increase the time for the operation to be completed.

#### 3.2 Restore
To restore a volume, the following interface is reserved:

```sh
$ volume restore <volumes-name>
```
To restore multiple volumes, separate them by space, example: `volume restore volume1 volume2`.

:pushpin: Note: If a volume already exists it will be overwritten.
:pushpin: Note: Make sure that the restore volume is not being used by any service.

*Optional parameters:*

- `--time` - You can restore from a particular backup by adding a time parameter to the command restore. For example, using restore `--time 3D `at the end in the above command will restore a backup from 3 days ago. See the [Duplicity manual](http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8) to view the accepted time formats.
- `--pre <path>` - Directory path that contains the scripts that will be executed before starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order.`;
-  `--pos <path>` - Directory path containing the scripts that will be executed after starting the backup or restore operation. All scripts that have the .sh extension will be executed in alphabetical order.;
-  `--remove-cache` - Parameter used to remove the cache volume used during the restore operation. The removal of this volume will cause, in the next backup operations, the synchronization of the directory where the backups are being sent. The synchronization will be done before the backup operation is performed. This may increase the time for the operation to be completed.


#### 3.3 Version

Command used to view the current version of the installed software.

```sh
$ volume version
```

#### 3.4 Version

Command used to view the operations and options of the installed software.

```sh
$ volume help
```

#### 3.5 Uninstall
Interface used to uninstall the program.

```sh
$ volume uninstall
```