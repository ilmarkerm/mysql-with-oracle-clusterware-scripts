#!/bin/bash

#
# This script uses logrotate to rotate all MySQL logfiles.
# It should be added to crontab on all instances, since it will send SIGHUP signal to all running MySQL instances, that will cause MySQL to switch to a new log
#
# 2012 Ilmar Kerm <ilmar.kerm@gmail.com>
#

# Load cluster instance configuration file
SCRIPTPATH=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTPATH`
source $SCRIPTDIR/instances.sh

LOCKFILE="$LOCKDIR/logrotate.lck"
DEFAULTLOGDIR="$LOGDIR"
LOGRCONF="$SCRIPTDIR/logrotate.conf"

if [[ ! -f "$LOCKFILE" ]]; then
  TEMPLATE="$LOCKFILE".XXXXXXXXX
  TEMPFILE=`mktemp "$TEMPLATE"`
  link "$TEMPFILE" "$LOCKFILE"
  if [[ $? -eq 0 ]]; then
    # Logrotate config headers
    echo "daily" > "$LOGRCONF"
    echo "missingok" >> "$LOGRCONF"
    echo "compress" >> "$LOGRCONF"
    echo "delaycompress" >> "$LOGRCONF"
    echo "nocreate" >> "$LOGRCONF"
    echo "dateext" >> "$LOGRCONF"
    echo "notifempty" >> "$LOGRCONF"
    echo "rotate 7" >> "$LOGRCONF"

    # Loop through all running instances
    for d in `ls $LOCKDIR/*.lock`; do
      instname=`basename "$d" ".lock"`
      # Read config
      LOGDIR=""
      TEMP_VAR1="$instname[*]"
      TEMP_VAR=${!TEMP_VAR1}
      declare $TEMP_VAR
      if [[ -z "$LOGDIR" ]]; then
        LOGDIR="$DEFAULTLOGDIR"
      fi
      #
      if [[ -n "$LOGDIR" ]]; then
        echo "$LOGDIR/$instname.err {}" >> "$LOGRCONF"
        echo "$LOGDIR/$instname.*.log {}" >> "$LOGRCONF"
      fi
    done
    
    # Execute logrotate
    logrotate -s "$SCRIPTDIR/logrotate.state" "$LOGRCONF"
    
    # Remove lockfile
    rm -f "$LOCKFILE"
  fi
  rm -f "$TEMPFILE"
fi

# Wait for the lock to be released
while [[ -f "$LOCKFILE" ]]; do
  sleep 5
done

# Send SIGHUP to all mysqld
# SIGHUP also flushes tables, so cannot use it to just rotate logs!!!
#killall -q -s SIGHUP mysqld

# Flush MySQL logfiles

flush_mysql_logs() {
  local i="$1"
  local TEMP_VAR1="$i[*]"
  local TEMP_VAR=${!TEMP_VAR1}
  local $TEMP_VAR
  $SOFTWARE/bin/mysqladmin -S "$DATADIR/mysql.sock" --user="$MYSQL_DB_USER" --password="$MYSQL_DB_PASSWORD" flush-logs
}

cd "$LOCKDIR"
hostname=`hostname`
for lockfile in `grep -li "$hostname" *.lock`; do
  instname=`basename "$lockfile" .lock`
  flush_mysql_logs "$instname"
done
