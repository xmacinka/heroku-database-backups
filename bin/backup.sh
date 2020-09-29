#!/bin/bash

# terminate script as soon as any command fails
set -e

hours=$(date +"%H")

echo "Hours: $hours"
echo "EVERY_N_HOURS: $EVERY_N_HOURS"
echo "HOURS_REMAINDER: $HOURS_REMAINDER"
echo "$((hours%($EVERY_N_HOURS)))"

if [ $((hours%($EVERY_N_HOURS))) != $HOURS_REMAINDER ]; then
  echo "Only running every N hours"
  exit 1
fi

if [[ -z "$APP" ]]; then
  echo "Missing APP variable which must be set to the name of your app where the db is located"
  exit 1
fi

if [[ -z "$DATABASE" ]]; then
  echo "Missing DATABASE variable which must be set to the name of the DATABASE you would like to backup"
  exit 1
fi

if [[ -z "$S3_BUCKET_PATH" ]]; then
  echo "Missing S3_BUCKET_PATH variable which must be set the directory in s3 where you would like to store your database backups"
  exit 1
fi

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
chmod +x ./aws/install
./aws/install -i /tmp/aws

BACKUP_FILE_NAME="$(date +"%Y-%m-%d-%H-%M")-$APP-$DATABASE.dump"

heroku pg:backups capture $DATABASE --app $APP

HEROKU_BACKUP_URL=`heroku pg:backups:url --app $APP`
echo $HEROKU_BACKUP_URL > 'last_backup_url.txt'
/tmp/aws/bin/aws s3 cp 'last_backup_url.txt' s3://$S3_BUCKET_PATH/$APP/last_backup_url.txt

curl -o $BACKUP_FILE_NAME $HEROKU_BACKUP_URL
FINAL_FILE_NAME=$BACKUP_FILE_NAME

if [[ -z "$NOGZIP" ]]; then
  gzip $BACKUP_FILE_NAME
  FINAL_FILE_NAME=$BACKUP_FILE_NAME.gz
fi


last_s3_backup_file=last_s3_backup.txt
format="%Y-%m-%d"
now=`date +"$format"`
last_s3_date=''


/tmp/aws/bin/aws s3 cp s3://$S3_BUCKET_PATH/$APP/$last_s3_backup_file $last_s3_backup_file


if [ -f $last_s3_backup_file ]; then
  last_s3_date=`cat $last_s3_backup_file`

  if [[ "$last_s3_date" != "$now" ]]; then
    last_s3_date='copy'
  fi
else
  last_s3_date='copy'
fi

if [[ "$last_s3_date" == "copy" ]]; then
  /tmp/aws/bin/aws s3 cp $FINAL_FILE_NAME s3://$S3_BUCKET_PATH/$APP/$DATABASE/$FINAL_FILE_NAME

  echo $now > $last_s3_backup_file
  /tmp/aws/bin/aws s3 cp $last_s3_backup_file s3://$S3_BUCKET_PATH/$APP/$last_s3_backup_file

  echo "backup $FINAL_FILE_NAME copied to S3"
fi

echo "backup $FINAL_FILE_NAME complete"

