#!/bin/bash
# Copy to /usr/local/bin/

# enable unofficial bash strict mode.
set -e -o pipefail

exit_hook() {
	echo "In exit_hook(), being killed" >&2
	jobs -p | xargs kill
	restic unlock
}

# exporting variables in order to simplify restic calls.
export RESTIC_REPOSITORY=$RESTIC_REPOSITORY
export RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE

# nextcloud folder containing the 'occ' executable.
nc=/usr/share/webapps/nextcloud
# always run occ as user 'http'.
run_as_http="runuser -u http --"
# command to activate Nextcloud maintenance mode.
maint_on=($run_as_http $nc/occ maintenance:mode --on)
# command to deactivate Nextcloud maintenance mode.
maint_off=($run_as_http $nc/occ maintenance:mode --off)

trap exit_hook INT TERM
# make sure Nextcloud maintenance mode is deactivated when script is exited.
trap "$maint_off" EXIT

# activate Nextcloud maintenance mode.
echo "Putting Nextcloud in maintenance."
eval "$maint_on" &

# source restic config.
. ~/.config/restic/nc.conf

# account for existing restic processes.
eval "restic unlock" &

# conduct the actual backup.
#  backup nextcloud folders.
eval "restic backup --tag $BACKUP_TAG $BACKUP_PATHS -x" &
wait $!
#  backup database.
eval "mysqldump --single-transaction -h localhost -u oc_root -pKF7WnFy+RmhS5FTIbT3vesMBCqwlHZ nextcloud | restic backup --stdin --tag $BACKUP_TAG" &
wait $!

# deactivate Nextcloud maintenance mode.
echo "Waking Nextcloud from maintenance."
eval "$maint_off" &

trap "" EXIT

# clean up.
eval "restic forget --tag $BACKUP_TAG --prune --group-by 'paths,tags' -l 3 & "
wait $!

echo "Restic - finished backing up and cleaning."
