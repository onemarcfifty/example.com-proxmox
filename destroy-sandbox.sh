#!/bin/bash

# ############################################
# This destroys all Containers and VMs
# of the example.com domain
# ############################################

# include the config file

. config

# The script needs to be run as root!
# if we are not root, we will exit

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

(cat) <<EOF
This will destroy all containers
and VMs of the $DOMAIN domain!!!

Please type Enter to continue or CTRL-C to abort
EOF
read

OPENWRTID=$(echo $CTID | cut -d "," -f 3 -)
qm stop $OPENWRTID
qm destroy $OPENWRTID

CLIENTID=$(echo $CTID | cut -d "," -f 1 -)
pct stop $CLIENTID
pct destroy $CLIENTID

DOCKERID=$(echo $CTID | cut -d "," -f 2 -)
pct stop $DOCKERID
pct destroy $DOCKERID


