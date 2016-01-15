#!/bin/bash
#
# Some helping functions shared between MySQL and PostgreSQL scripts
# Ilmar Kerm, 2012
# http://code.google.com/p/postgresql-with-oracle-clusterware-scripts/

writelog() {
  local crscode
  local syslogcode
  
  case "$2" in
    w) crscode="CRS_WARNING"
       syslogcode="user.warning"
       ;;
    e) crscode="CRS_ERROR"
       syslogcode="user.err"
       ;;
    *) crscode="CRS_PROGRESS"
       syslogcode="user.notice"
       ;;
  esac
  
  # Write log message to stdout for clusterware log and to syslog
  echo "$crscode $1"
  echo "$1" | logger -t "$SYSLOGTAG" -p "$syslogcode"
}

read_info_from_lockfile() {
  if [ -f "$LOCKFILE" ]; then
    local lines=($(cat $LOCKFILE))
    LOCK_HOSTNAME=${lines[0]}
    LOCK_PID=${lines[1]}
  else
    LOCK_HOSTNAME=""
    LOCK_PID=""
  fi
}
