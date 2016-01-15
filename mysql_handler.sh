#!/bin/bash
#
# This script handles all MySQL operations for Oracle Clusterware. Available actions:
# start - Starts specified MySQL instance
# stop - Stops MYSQL instance
# check - Checks if MySQL is alive
# clean - Forcefully stops MySQL instance
# All other actions start MySQL console
#
# Script requires environment variable MYSQL_SID that specified the MySQL instance name
# and instance parameters must be configured in instances.sh file

# Ilmar Kerm, 2011, 2012
# http://code.google.com/p/mysql-with-oracle-clusterware-scripts/


# Checking if MYSQL_SID exists
if [ ! $MYSQL_SID ]; then
    echo "MYSQL_SID must be specified"
    exit 1
fi

# Load cluster instance configuration file
SCRIPTPATH=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTPATH`
source $SCRIPTDIR/instances.sh
source $SCRIPTDIR/functions.sh

# Read the correct instance config
# Here is should declare DATADIR BINDADDR and SOFTWARE
TEMP_VAR1="$MYSQL_SID[*]"
TEMP_VAR=${!TEMP_VAR1}
declare -r $TEMP_VAR

# Declare other MySQL file locations
HOSTNAME=`hostname`
PIDFILE=$DATADIR/$HOSTNAME.pid
SOCKET=$DATADIR/mysql.sock
LOGFILE=$LOGDIR/$MYSQL_SID.err
SLOWLOGFILE=$LOGDIR/$MYSQL_SID.slow.log
GENLOGFILE=$LOGDIR/$MYSQL_SID.gen.log
LOCKFILE=$LOCKDIR/$MYSQL_SID.lock
SYSLOGTAG=mysql_$MYSQL_SID
exitval=0

# Does config file actually exist
if [ ! -f "$CONFFILE" ]; then
    echo "$CONFFILE not found"
    exit 1
fi

# Does DATADIR actually exist and contain valid MySQL data dir
if [ ! -d "$DATADIR/mysql" ]; then
    echo "$DATADIR does not seem to be a valid MySQL data directory"
    exit 1
fi

# Is SOFTWARE a valid MySQL software installation
if [ ! -f "$SOFTWARE/bin/mysqld_safe" ]; then
    echo "$SOFTWARE does not seem to be a valid MySQL installation directory"
    exit 1
fi

# Get MySQL PID if pidfile exists
MYSQLPID=0
if [ -f "$PIDFILE" ]; then
  pid=`cat "$PIDFILE"`
  if [ $pid -gt 0 ]; then
    MYSQLPID=$pid
  else
    MYSQLPID=0
  fi
fi


# For clusterware logfile
if [[ -n "$_CRS_NAME" ]]; then
  echo "`date` Action script '$_CRS_ACTION_SCRIPT' for resource[$_CRS_NAME] called for action $1 - MYSQL_SID=$MYSQL_SID"
fi

is_pid_valid() {
  local returnval
  local procfile
  local grepstr
  local linecount
  local pid
  returnval=1
  
  if [ $MYSQLPID -gt 0 ]; then
    # Look into the process commandline to check if it is MySQL and with correct pidfile
    procfile=/proc/$MYSQLPID/cmdline
    if [ -f "$procfile" ]; then
      grepstr=$(printf "%s\n%s\n" "mysqld" "$PIDFILE")
      linecount=`strings $procfile | grep -F "$grepstr" | wc -l`
      if [ $linecount -eq 2 ]; then
        returnval=0
      fi
    fi
  fi

  return $returnval
}

clean() {
  read_info_from_lockfile
  # If still alive, send KILL
  if is_pid_valid; then
    writelog "Still alive, sending KILL..."
    kill -9 "$MYSQLPID"
    sleep 1
  fi
  # Try killing the PID in lockfile
  if [[ "$HOSTNAME" == "$LOCK_HOSTNAME" ]]; then
    MYSQLPID=$LOCK_PID
    if is_pid_valid; then
      writelog "Lockfile PID still alive, sending KILL..."
      kill -9 "$MYSQLPID"
      sleep 1
    fi
    rm -f $LOCKFILE
  fi
  # Remove pidfile
  if [ -f "$PIDFILE" ]; then
    rm -f "$PIDFILE"
  fi
}

stop() {
  # Send kill signal to MySQL process
  if [ $MYSQLPID -gt 0 ]; then
    echo "Stopping MySQL"
    kill "$MYSQLPID" > /dev/null 2> /dev/null
    # Try to wait a little, until mysqld has exited
    for i in {1..10}; do
      kill -0 "$MYSQLPID" > /dev/null 2> /dev/null || break
      sleep 2
    done
    kill -0 "$MYSQLPID" > /dev/null 2> /dev/null
    if [[ $? -eq 0 ]]; then
      echo "CRS_WARNING mysqld is still stopping, exiting in failed state"
      exitval=1
    else
      rm -f $LOCKFILE
      exitval=0
    fi
  fi
}

ping_instance() {
  # Try connecting to the instance
  RESPONSE=`$SOFTWARE/bin/mysqladmin --no-defaults --socket=$SOCKET --user=UNKNOWN ping 2>&1`
  if [[ $? -eq 0 ]]; then
    return 0
  else
    echo "$RESPONSE" | grep -q "Access denied for user"
    if [[ $? -eq 0 ]]; then
      return 0
    else
      return 1
    fi
  fi
}

start() {
  read_info_from_lockfile
  # Issue a warning, but assume clusterware deals with that situation
  if [[ -n "$LOCK_HOSTNAME" && "$HOSTNAME" != "$LOCK_HOSTNAME" ]]; then
    writelog "CRS_WARNING Found leftover lockfile from host $LOCK_HOSTNAME..." w
    if [[ -n "$_CRS_NAME" ]]; then
      if [[ `stat -c %Z "$LOCKFILE"` -ge `date --date="40 second ago" +%s` ]]; then
        writelog "Lockfile updated too recently" e
        exit 1
      else
        writelog "Continuing to start up, clusterware should prevent double startups"
      fi
    else
      writelog "Since clusterware environment was not found, cancelling startup. If the same instance is not running on the other node, then remove $LOCKFILE before trying again." e
      exit 1
    fi
  fi
  
  # If local pidfile exists, check if it is indeed MySQL and then issue kill
  if is_pid_valid; then
    writelog "MySQL already running..."
    stop
  fi

  # Add note to error log file
  if [[ -f $LOGFILE ]]; then
    echo "### $MYSQL_SID starting on '$HOSTNAME'" >> $LOGFILE
  fi
  # Start mysql
  cd $SOFTWARE
  ./bin/mysqld --defaults-file=$CONFFILE \
    --datadir=$DATADIR --user=$MYSQLUSER --pid-file=$PIDFILE \
    --socket=$SOCKET --bind-address=$BINDADDR \
    --basedir=$SOFTWARE \
    --log-error=$LOGFILE --slow-query-log-file=$SLOWLOGFILE --general-log-file=$GENLOGFILE \
    >/dev/null 2>&1 &

  # Get mysqld PID
  # Write lockfile
  echo "$HOSTNAME" > "$LOCKFILE"
  jobs -p >> "$LOCKFILE"
  # If times out, then starting is successful, and check should return PARTIAL status
  exitval=0
  # Wait for PID file
  for i in {1..10}; do
    if [ -f $PIDFILE ]; then
      # Try connecting
      if ping_instance; then
        disown %+
        break
      fi
    fi
    # Check if bash job still exists
    jobs %+ > /dev/null 2> /dev/null
    if [[ $? -eq 0 ]]; then
      writelog "Waiting to start"
      sleep 3
    else
      writelog "Error starting MySQL. Here are 5 last ERROR lines from '$LOGFILE':" e
      grep "ERROR" $LOGFILE | tail -5
      rm -f "$LOCKFILE"
      exitval=1
      break
    fi
  done
}

check() {
  read_info_from_lockfile
  # If no pid, then fail immediately
  if ! is_pid_valid; then
    if [[ "$HOSTNAME" == "$LOCK_HOSTNAME" ]]; then
      # Lock file is created by the same host
      MYSQLPID=$LOCK_PID
      if is_pid_valid; then
        writelog "MySQL process exists, but no PID" w
        exit 4
      else
        writelog "No pid, unplanned shutdown" w
        rm -f "$LOCKFILE"
        exit 1
      fi
    elif [[ -z "$LOCK_HOSTNAME" ]]; then
      # No lockfile
      writelog "No pid, planned shutdown"
      exit 2
    else
      # Lock file is from different host
      writelog "No pid, different host" w
      exit 1
    fi
  fi
  
  # if pid exists, but lockfile is from different host, then stop
  if [[ "$HOSTNAME" != "$LOCK_HOSTNAME" ]]; then
    writelog "Lock file is from different host, failing" e
    exit 5
  fi

  # Use mysqladmin ping to check if server is responding
  local RESPONSE=`$SOFTWARE/bin/mysqladmin --no-defaults -S $SOCKET -u $MYSQL_DB_USER -p"$MYSQL_DB_PASSWORD" ping 2>&1`
  if [[ $? -eq 0 || "$RESPONSE" == *"Access denied for user"* ]]; then
    # Renew lockfile timestamp
    touch "$LOCKFILE"
    exit 0
  else
    if [[ "$MYSQLPID" == "$LOCK_PID" ]]; then
      writelog "Database not accessible, but process is up, assuming PARTIAL"
      touch "$LOCKFILE"
      exit 4
    else
      # Issue kill command
      writelog "Server is not accessible, killing" e
      stop
      exit 1
    fi
  fi
}

console() {
  # Execute MySQL console
  $SOFTWARE/bin/mysql -S $SOCKET <&0
  exit $?
}

case "$1" in
  start)
    start
;;
  stop)
    stop
;;
  restart)
    stop
    sleep 2
    start
;;
  check)
    check
;;
  clean)
    clean
;;
  *)
    echo $"Usage: $0 {start|stop|restart|check|clean}. All other arguments execute MySQL Console."
    console
esac

exit $exitval
