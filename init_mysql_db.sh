#!/bin/bash

# The purpose of this script is to:
# 1) initialize MySQL data directory
# 2) change MySQL root password and create a dedicated MySQL user for clusterware monitoring
# 3) prepare configuration files and create clusterware actionscript
# 4) create clusterware resources for the created MySQL instance

# Ilmar Kerm, 2011-2013
# http://code.google.com/p/mysql-with-oracle-clusterware-scripts/

# Global variables
SCRIPTPATH=`readlink -f $0`
SCRIPTDIR=`dirname $SCRIPTPATH`
CLUSTERCONFIG=$SCRIPTDIR/instances.sh

# Read mysql user from global configuration
source $CLUSTERCONFIG

DATADIR=""
SOFTWAREDIR=""
LOGDIR=""
BINDADDR=""
CONFIGFILE=""
INSTNAME=""
UPDATECONFIG=0
ADDGRIDRES=1
INITUSERS=0

# INI file reader
source $SCRIPTDIR/read_ini.sh

help() {
  echo ""
  echo "This script initializes MySQL data directory and all cluster scripts."
  echo "Script must be run as user root."
  echo "Usage:"
  echo "-i name"
  echo "	Instance name. Name should be 20 characters or less and only characters a-z, A-Z, 0-9 and _ are allowed (\w character class)"
  echo
  echo "MySQL and instance settings:"
  echo
  echo "-s directory"
  echo "	MySQL software location (where tar-edition is unpacked)"
  echo "-b ipaddr"
  echo "	IP address to bind the instance"
  echo "-a basedirectory"
  echo "	Instance base directory, this replaces options -d -c -l by setting the following values"
  echo "	-d basedirectory/data, -c basedirectory/config/my.cnf, -l basedirectory/logs"
  echo "-d directory"
  echo "	Empty MySQL data directory to initialize"
  echo "-c file"
  echo "	MySQL config file for this instance"
  echo "-l directory"
  echo "	MySQL error/slow/general logfile directory for this instance"
  echo
  echo "Additional configuration:"
  echo
  echo "-x"
  echo "	Do not update instances.sh"
  echo "-u"
  echo "	Do not set mysql root password and clusterware user (creating user requires starting mysqld and default password specified in /root/.my.cnf)"
  echo "-g"
  echo "	Add resources to clusterware (VIP and application)"
}

checkparams() {
  local EXITVAL=0
  
  # Check if user is root
  if [[ `id -u` -ne "0" ]]; then
    echo "* This script must be run as user root" >&2
    EXITVAL=1
  fi
  
  # Check if instances.sh is writable
  if [[ ! -w $CLUSTERCONFIG && $UPDATECONFIG -eq "0" ]]; then
    echo "* \"$CLUSTERCONFIG\" does not exist or is not writable." >&2
    EXITVAL=1
  fi
  
  # Is instance name present and correct
  local inst_match=1
  #if [[ $INSTNAME =~ "^\w+$" ]]; then
  if [[ `echo "$INSTNAME" | grep -E "^\w+$" | wc -l` -eq 1 ]]; then
    inst_match=0
  fi
  if [[ -z "$INSTNAME" || ${#INSTNAME} -ge 20 || $inst_match -ne "0" ]]; then
    echo "* Instance name \"$INSTNAME\" is not correct. $inst_match" >&2
    EXITVAL=1
  fi
  # Does this instance name already exist
  if [[ $UPDATECONFIG -eq "0" && -n "${!INSTNAME}" ]]; then
    echo "* Instance \"$INSTNAME\" is already configured in $CLUSTERCONFIG." >&2
    EXITVAL=1
  fi

  # Check data directory
  if [[ -z "$DATADIR" || ! -d $DATADIR || "$(ls -A $DATADIR)" ]]; then
    echo "* Data directory \"$DATADIR\" must exist and be empty." >&2
    EXITVAL=1
  fi
  
  # Check log directory
  if [[ -z "$LOGDIR" || ! -d $LOGDIR ]]; then
    echo "* Log directory \"$LOGDIR\" must exist." >&2
    EXITVAL=1
  fi
  
  # Check software directory
  if [[ -z "$SOFTWAREDIR" || ! -d $SOFTWAREDIR || ! -f $SOFTWAREDIR/bin/mysqld || ! -f $SOFTWAREDIR/scripts/mysql_install_db ]]; then
    echo "* Software directory \"$SOFTWAREDIR\" must be directory where you untarred the MySQL tar-edition." >&2
    EXITVAL=1
  fi
  
  # Check IP address
  if [[ $UPDATECONFIG -eq "0" && -z "$BINDADDR" ]]; then
    echo "* Bind IP address must be specified." >&2
    EXITVAL=1
  fi
  
  # Does MySQL user exist
  local tmpval=0
  tmpval=`id -u $MYSQLUSER`
  if [[ $? -ne 0 ]]; then
    echo "* MySQL user not found: $MYSQLUSER." >&2
    EXITVAL=1
  fi
  
  # Check config file
  if [[ -z "$CONFIGFILE" && $UPDATECONFIG -eq "0" ]]; then
    echo "* Config file location must be specified." >&2
    EXITVAL=1
  fi
  if [[ -n "$CONFIGFILE" && $UPDATECONFIG -eq "0" && ! -f $CONFIGFILE ]]; then
    echo "* Config file not found." >&2
    EXITVAL=1
  fi

  return $EXITVAL
}

init_data_dir() {
  local EXITVAL=0
  local uid=0
  local gid=0
  
  uid=`id -u $MYSQLUSER`
  gid=`id -g $MYSQLUSER`
  
  # Chown logdir
  chown $uid:$gid $LOGDIR
  # Chown and init mysql data dir
  chown $uid:$gid $DATADIR
  $SOFTWAREDIR/scripts/mysql_install_db --skip-name-resolve --basedir=$SOFTWAREDIR --datadir=$DATADIR --user=$MYSQLUSER --no-defaults
  EXITVAL=$?
  
  return $EXITVAL
}

init_users() {

  local password=""
  
  # Does the ini file exist
  if [ -f /root/.my.cnf ]; then 
    # Parse ini file
    read_ini /root/.my.cnf
    if [[ ${INI__mysql__user} = "root" ]]; then
      password="${INI__mysql__password}"
    elif [[ ${INI__client__user} = "root" ]]; then
      password="${INI__client__password}"
    fi
  fi
  
  # Start mysqld with default parameters
  echo "Starting MySQL..."
  cd $SOFTWAREDIR
  local SOCKET=$DATADIR/mysql.sock
  local PIDFILE=$DATADIR/`hostname`.pid
  if [[ "$MYSQL_VERSION" == "5.5" ]]; then
    ./bin/mysqld_safe --datadir=$DATADIR --user=$MYSQLUSER --socket=$SOCKET --basedir=$SOFTWARE --pid-file=$PIDFILE \
      --skip-networking --skip-name-resolve --skip-innodb --default-storage-engine=myisam --log-error=$LOGDIR/$INSTNAME.err >/dev/null 2>&1 &
  elif [[ "$MYSQL_VERSION" == "5.6" ]]; then
    ./bin/mysqld_safe --datadir=$DATADIR --user=$MYSQLUSER --socket=$SOCKET --basedir=$SOFTWARE --pid-file=$PIDFILE \
      --skip-networking --skip-name-resolve --default-storage-engine=myisam --log-error=$LOGDIR/$INSTNAME.err >/dev/null 2>&1 &
  fi
  sleep 5

  # Create clusterware user
  if [[ -n "$MYSQL_DB_USER" && -n "$MYSQL_DB_PASSWORD" ]]; then
    echo "Creating '$MYSQL_DB_USER'@'localhost' user..."
    echo "create user '$MYSQL_DB_USER'@'localhost' identified by '$MYSQL_DB_PASSWORD'; grant reload on *.* to '$MYSQL_DB_USER'@'localhost';" | \
      ./bin/mysql --no-defaults -S $SOCKET -u root
  else
    echo "Clusterware username or password not found in instances.sh (parameters MYSQL_DB_USER and MYSQL_DB_PASSWORD). Please create the user manually." >&2
  fi

  if [[ -n "$password" ]]; then
    # Change root password
    echo "Changing root password..."
    ./bin/mysqladmin --no-defaults -S $SOCKET -u root password $password
  else
    echo "Default root password not found in /root/.my.cnf. MySQL root password was not changed!!" >&2
  fi
  
  # Stop mysqld
  if [[ -f $PIDFILE ]]; then
    echo "Stopping MySQL..."
    kill `cat $PIDFILE`
  else
    echo "MySQL pid file not found... did it crash or not start at all?" >&2
    EXITVAL=1
  fi

  return $EXITVAL
}

update_config() {

  echo "Updating cluster configuration $CLUSTERCONFIG..."
  local FILENAME=$CLUSTERCONFIG
  echo "" >> $FILENAME
  echo "$INSTNAME=(" >> $FILENAME
  echo "  DATADIR=\"$DATADIR\"" >> $FILENAME
  echo "  CONFFILE=\"$CONFIGFILE\"" >> $FILENAME
  echo "  BINDADDR=\"$BINDADDR\"" >> $FILENAME
  echo "  SOFTWARE=\"$SOFTWAREDIR\"" >> $FILENAME
  echo "  LOGDIR=\"$LOGDIR\"" >> $FILENAME
  echo ")" >> $FILENAME
  
  # Symlink actionscript
  echo "Symlinking actionscript $INSTNAME.scr..."
  cd $SCRIPTDIR
  ln -s action_handler.scr $INSTNAME.scr
  
  return 0
}

get_mysql_version() {
  local OUTPUT
  OUTPUT=`$SOFTWAREDIR/bin/mysqld --version`
  if [[ "$OUTPUT" == *"Ver 5.5."* ]]; then
    MYSQL_VERSION="5.5"
  elif [[ "$OUTPUT" == *"Ver 5.6."* ]]; then
    MYSQL_VERSION="5.6"
  else
    MYSQL_VERSION="-"
  fi
}


# Check if script was executed without arguments
if [ $# -eq 0 ]; then
  help
  exit 1
fi

# Parse supplied arguments
while getopts ":d:s:b:c:xgui:l:a:" opt; do
  case $opt in
    a)
      # Base directory
      DATADIR=$OPTARG/data
      LOGDIR=$OPTARG/logs
      CONFIGFILE=$OPTARG/config/my.cnf
      ;;
    d)
      # Data directory
      DATADIR=$OPTARG
      ;;
    l)
      # Log directory
      LOGDIR=$OPTARG
      ;;
    s)
      # Software directory
      SOFTWAREDIR=$OPTARG
      ;;
    x)
      # Do not update config file
      UPDATECONFIG=1
      ;;
    g)
      # Add clusterware resources
      ADDGRIDRES=0
      ;;
    i)
      # Instance name
      INSTNAME=$OPTARG
      ;;
    b)
      # Bind address
      BINDADDR=$OPTARG
      ;;
    c)
      # Config file
      CONFIGFILE=$OPTARG
      ;;
    u)
      # Do not init user passwords
      INITUSERS=1
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

# Check mysql version
get_mysql_version
if [[ "$MYSQL_VERSION" == "-" ]]; then
  echo "Unsupported MySQL version" >&2
  exit 1
fi


# If all is OK, then initialize
if ! init_data_dir; then
  echo "Error when initializing MySQL data directory" >&2
  exit 1
fi

# Initialize user passwords
if [[ $INITUSERS -eq "0" ]]; then
  init_users
fi

# Change cluster config
if [[ $UPDATECONFIG -eq "0" ]]; then
  update_config
fi

# Add clusterware resources
if [[ $ADDGRIDRES -eq "0" ]]; then
  $SCRIPTDIR/init_grid.sh -i $INSTNAME
fi
