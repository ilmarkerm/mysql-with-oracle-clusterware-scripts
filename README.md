# MySQL with Oracle Clusterware scripts

Author: [Ilmar Kerm](https://ilmarkerm.eu/)

The collection of Bash scripts that help to manage multiple MySQL instances inside cluster managed by Oracle Clusterware 11gR2. Each MySQL instance running inside this cluster is configured with a dedicated IP address (Virtual IP resource in clusterware).

The scripts manage:

* Initializing MySQL data directory and configuring resources in Oracle Clusterware.
* Clusterware actionscript to manage instance startup, shutdown, cleanup and check.
* All scripts are built with support of running multiple MySQL instances in the same cluster.
* Each MySQL instance can run with different MySQL software version.
* Automatic MySQL error/slow/general log rotation and archival.

Although these scripts are written with clusterware in mind, they can also be used without it - to help managing multiple MySQL instances (with different RDBMS versions) running in the same host.

[Read the full documentation here](https://ilmarkerm.eu/blog/mysql-high-availability-with-oracle-clusterware/)
