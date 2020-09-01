# Volumes Docker Backup

## Prerequisites
1. Linux _(Ubuntu 16.04+ recommended)_
2. Docker Engine 18.06.0+
   - Follow all the steps present in the [official documentation](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce).

## Drescription

Project to backup and restore Docker volumes. In addition to performing local backups, you can perform backups on Amazon AWS S3 and Google Driver.

### 1. Set the environment variables

Variables responsible for defining backup settings. The variables with prefix `CLOUD` are commented out by default, to activate them uncommented and set their respective value based on the values provided by the cloud service that you want to perform the backups and restores. The supported cloud storage services are Google Drive and AWS S3.

In order for backup and restore operations to be successful, credentials must be granted permissions to manipulate the cloud storage location:
    
- [Google Drive](https://console.developers.google.com/apis/credentials)
When performing the first backup, a link will be provided that redirects the browser to a user's authentication screen at Google, thus granting permission to manipulate Google Drive. In future `backup` or `restore` operations, authentication is not required unless the `ocariot-credentials-data` volume is removed.

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

### 2. Interface commands

#### 2.1 Backup

To perform a backup generation, the following interface is reserved:

```sh
$ ./volume backup <volume-name>
```

:pushpin: Note: Make sure that the volume to be backed up is not in use by any services.

#### 2.2 Restore
To restore a volume, the following interface is reserved:

```sh
$ ./volume restore <volume-name>
```

:pushpin: Note: If a volume already exists it will be overwritten.

*Optional parameters:*

- `--time` - You can restore from a particular backup by adding a time parameter to the command restore. For example, using restore `--time 3D `at the end in the above command will restore a backup from 3 days ago. See the [Duplicity manual](http://duplicity.nongnu.org/vers7/duplicity.1.html#toc8) to view the accepted time formats.