# This script is just configuration file, it contains some general parameters and the
# configuration for all MySQL instances

# Ilmar Kerm, 2011, 2012
# http://code.google.com/p/mysql-with-oracle-clusterware-scripts/

# MySQL OS process owner
MYSQLUSER=mysql

# MYSQL_DB_USER MYSQL_DB_PASSWORD - Credentials to log in to mysql, does not need any privileges at all, just connect:
# MYSQL_DB_USER MYSQL_DB_PASSWORD - Credentials to log in to mysql, does not need any privileges at all, just connect:
#   create user 'clusterware'@'localhost' identified by 'cluster123';
# These settings can be overriden inside instance specific settings also
MYSQL_DB_USER="clusterware"
MYSQL_DB_PASSWORD="cluster123"

LOCKDIR=/u02/app/mysql/locks

# For each instance declare:
# DATADIR - MySQL data directory
# CONFFILE - MySQL config file
# BINDADDR - IP to bind to
# SOFTWARE - used MySQL software home directory ($SOFTWARE/bin should include mysqld binary)

first_instance=(
  DATADIR="/instance/first_instance/data"
  CONFFILE="/instance/first_instance/config/my.cnf"
  BINDADDR="10.0.1.1"
  SOFTWARE="/u02/app/mysql/product/5.5.16/advanced"
  LOGDIR="/instance/logs"
)

sample_instance=(
  DATADIR="/instance/sample_instance/data"
  CONFFILE="/instance/sample_instance/config/my.cnf"
  BINDADDR="10.0.1.2"
  SOFTWARE="/u02/app/mysql/product/5.5.16/advanced"
  LOGDIR="/instance/logs"
)

