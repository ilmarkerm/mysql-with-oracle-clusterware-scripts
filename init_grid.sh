#!/bin/bash

# The purpose of this script is to:
# 1) create clusterware resources for the created MySQL instance

# Ilmar Kerm, 2011-2013
# http://code.google.com/p/mysql-with-oracle-clusterware-scripts/

# Global variables
SCRIPTPATH=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTPATH`
CLUSTERCONFIG=$SCRIPTDIR/instances.sh

# Read mysql user from global configuration
source $CLUSTERCONFIG

INSTNAME=""
IPADDR=""
LOAD=10
SERVER_POOL="Generic"
GRID_HOME=""
GRID_USER=""
VIPNAME=""
TYPE="cluster_resource"
DEPENDENCIES=""

help() {
  echo ""
  echo "This script initializes MySQL instance in Oracle Clusterware, by creating virtual IP resource and application resource."
  echo "Script must be run as user root."
  echo "Usage:"
  echo "-i name"
  echo "	Instance name. Name should be 20 characters or less and only characters a-z, A-Z, 0-9 and _ are allowed (\w character class)"
  echo "-t type (default cluster_resource)"
  echo "	Resource type"
  echo "-p pool name (default Generic)"
  echo "	Server pool name"
  echo "-l number (default 10)"
  echo "	Instance load attribute"
  echo "-d comma separated list of clusterware resource names"
  echo "	List of clusterware resources that this mysql instance has a hard dependency on (for example ACFS filesystems) - example: ora.data.u02.acfs,ora.data.instd1.acfs"
}

checkparams() {
  local EXITVAL=0
  
  # Check if user is root
  if [[ `id -u` -ne "0" ]]; then
    echo "* This script must be run as user root"
    EXITVAL=1
  fi
  
  # Does this instance name exist
  if [[ -z "${!INSTNAME}" ]]; then
    echo "* Instance \"$INSTNAME\" is not configured in $CLUSTERCONFIG."
    EXITVAL=1
  fi
  
  # Check if load and check timeout are numbers
  if ! [[ "$LOAD" =~ ^[0-9]+$ ]]; then
    echo "Load must be integer"
    EXITVAL=1
  fi
  
  return $EXITVAL
}



# Check if script was executed without arguments
if [ $# -eq 0 ]; then
  help
  exit 1
fi

# Parse supplied arguments
while getopts ":i:l:t:p:d:" opt; do
  case $opt in
    l)
      # Load
      LOAD=$OPTARG
      ;;
    i)
      # Instance name
      INSTNAME=$OPTARG
      VIPNAME=$INSTNAME"_vip"
      ;;
    t)
      # Check interval
      TYPE="$OPTARG"
      ;;
    p)
      # Server pool
      SERVER_POOL="$OPTARG"
      ;;
    d)
      # Hard dependencies
      DEPENDENCIES="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      help
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      help
      exit 1
      ;;
  esac
done

# Check supplied parameters
if ! checkparams; then
  help
  exit 1
fi

echo "Instance name=$INSTNAME"

# Determine Oracle Clusterware user and path
GRID_PS=`ps -C ocssd.bin -o uname,cmd h`
if [[ $? -ne 0 ]]; then
  echo "Oracle Clusterware not running (ocssd.bin not running)" >&2
  exit 1
fi

i=0
for f in $GRID_PS; do
  if [[ $i -eq 0 ]]; then
    GRID_USER=$f
  elif [[ $i -eq 1 ]]; then
    GRID_HOME=${f%"/bin/ocssd.bin"}
  else
    break
  fi
  ((i++))
done

echo "GRID_USER=$GRID_USER"
echo "GRID_HOME=$GRID_HOME"

# Check if resources already exist
$GRID_HOME/bin/crs_stat $INSTNAME > /dev/null
if [[ $? -eq 0 ]]; then
  echo "Clusterware already has resource '$INSTNAME' configured" >&2
  exit 1
fi

$GRID_HOME/bin/crs_stat $VIPNAME > /dev/null
if [[ $? -eq 0 ]]; then
  echo "Clusterware already has resource '$VIPNAME' configured" >&2
  exit 1
fi

# Read the correct instance config
# Here is should declare BINDADDR
TEMP_VAR1="$INSTNAME[*]"
TEMP_VAR=${!TEMP_VAR1}
declare -r $TEMP_VAR

if [[ -z "$BINDADDR" ]]; then
  echo "BINDADDR not found in instance configuration" >&2
  exit 1
else
  echo "Virtual IP=$BINDADDR"
fi

# Check if server is already listening of that IP
if [[ `ip addr show | grep "inet $BINDADDR" | wc -l` -ne 0 ]]; then
  echo "Server is already listening on '$BINDADDR'" >&2
  exit 1
fi

# Try pinging
ping -c 2 -q $BINDADDR > /dev/null
if [[ $? -eq 0 ]]; then
  echo "Got a ping reply on '$BINDADDR'" >&2
  exit 1
fi

# Add resources to clusterware
# VIP
$GRID_HOME/bin/appvipcfg create -network=1 -ip=$BINDADDR -vipname=$VIPNAME -user=root
$GRID_HOME/bin/crsctl setperm resource $VIPNAME -o root
$GRID_HOME/bin/crsctl setperm resource $VIPNAME -u user:$GRID_USER:r-x
$GRID_HOME/bin/crsctl modify resource $VIPNAME -attr "PLACEMENT='restricted', SERVER_POOLS='$SERVER_POOL', HOSTING_MEMBERS=''"

HARDDEPS="$VIPNAME"
if [[ -n "$DEPENDENCIES" ]]; then
  HARDDEPS+=",$DEPENDENCIES"
fi
RES_ATTR="ACTION_SCRIPT=$SCRIPTDIR/$INSTNAME.scr, PLACEMENT='restricted', LOAD=$LOAD, SERVER_POOLS='$SERVER_POOL', START_DEPENDENCIES='hard($HARDDEPS) pullup($VIPNAME)', STOP_DEPENDENCIES='hard($HARDDEPS)'"
$GRID_HOME/bin/crsctl add resource $INSTNAME -type $TYPE -attr "$RES_ATTR"
$GRID_HOME/bin/crsctl setperm resource $INSTNAME -o root
$GRID_HOME/bin/crsctl setperm resource $INSTNAME -u user:$GRID_USER:r-x

echo "Configuration done!"
echo "Use the following command to start MySQL instance:"
echo "	$GRID_HOME/bin/crsctl start resource $INSTNAME"
