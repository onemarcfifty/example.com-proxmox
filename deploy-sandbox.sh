#!/bin/bash

# ############################################
# This is the main deploy script
# that creates all the containers for the
# example.com domain
# ############################################

# include the config file
. config

# The script needs to be run as root!
# if we are not root, we will exit
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# ask for consent and abort or start the installation
(cat) <<EOF
This will install a virtual network 
on your Proxmox VE host.
the parameters that you have chosen are:

Domain name:           $DOMAIN
Virtual LAN interface: $LAN
Virtual WAN interface: $WAN
Container Storage:     $STORAGE

Please type Enter to continue or CTRL-C to abort
EOF
read

echo "Please specify a root password for the containers (input not shown)"
read -s ROOTPASSWD
echo "Please specify a non-root user name for the client container"
read NONROOTUSER
echo "Please specify a password for the non-root user (input not shown)"
read -s NONROOTPASSWD


# #########################################
echo "##### finding the template"
# #########################################

pveam download $TEMPLATESTORAGE $TEMPLATENAME
CTTEMPLATE=$(pveam list $TEMPLATESTORAGE |grep $TEMPLATENAME | cut -d " " -f 1 -)
if [ "X" == "X${CTTEMPLATE}" ]; then
  echo "Template not available - exiting"
  exit
fi

# #########################################
echo "##### deploying the router"
# #########################################

OPENWRTID=$(echo $CTID | cut -d "," -f 3 -)
qm create $OPENWRTID --cores 1 --name "exc-OpenWrt" --net0 model=virtio,bridge=$LAN --net1 model=virtio,bridge=$WAN --storage $STORAGE --memory 512
wget -q -O - $OPENWRTURL | gunzip -c >/tmp/openwrt.img
qm importdisk $OPENWRTID /tmp/openwrt.img $STORAGE --format qcow2
qm set $OPENWRTID --ide0 $STORAGE:vm-$OPENWRTID-disk-0
qm set $OPENWRTID --boot order=ide0
rm /tmp/openwrt.img
qm start $OPENWRTID

echo -e "\n ######### Please make sure the router has internet access"
echo -e " ######### (open a shell on the VM and ping www.google.com or the like)"
echo -e "\n ######### press ENTER to continue\n"
read

# #########################################
echo "##### deploying the client"
# #########################################

CLIENTID=$(echo $CTID | cut -d "," -f 1 -)
pct create $CLIENTID $CTTEMPLATE \
    --cores 1 \
    --description "RDP Server for the ${DOMAIN} domain" \
    --hostname "exc-Client" \
    --memory 2048 \
    --password "$ROOTPASSWD" \
    --storage $STORAGE \
    --net0 name=eth0,bridge=$WAN,ip=dhcp \
    --net1 name=eth1,bridge=$LAN,ip=dhcp \
    --features nesting=1 \
    --unprivileged 1

# #########################################
echo "##### deploying the docker-host"
# #########################################

DOCKERID=$(echo $CTID | cut -d "," -f 2 -)
pct create $DOCKERID $CTTEMPLATE \
    --cores 1 \
    --description "Docker host for the ${DOMAIN} domain" \
    --hostname "exc-Docker" \
    --memory 2048 \
    --password "$ROOTPASSWD" \
    --storage $STORAGE \
    --net0 name=eth1,bridge=$LAN,ip=dhcp \
    --features keyctl=1,nesting=1 \
    --unprivileged 1

echo -e "\n ######### Please check the settings of the containers in the Proxmox GUI \n ######### press ENTER to continue\n"
read


# #########################################
echo "##### starting the containers"
# #########################################

# start the containers
pct start $CLIENTID
pct start $DOCKERID

# #########################################
echo -e "\n ##### creating self-signed certs \n"
# #########################################

# in case the domain is not called example.com, let's bluntly replace it in the config file
sed -i s/example.com/${DOMAIN}/ imap.cnf
sed -i s/example.com/${DOMAIN}/ wildcard.cnf

# create the Certificates - first the CA
openssl req -newkey rsa:2048 -keyout rootCA.key -x509 -days 3650 -nodes -out rootCA.crt -subj "/CN=AAA_TestCA/C=DE/O=AAA_onemarcfifty/emailAddress=admin@${DOMAIN}"

# now the CSR and cert for the *.example.com wildcard
openssl req -newkey rsa:2048 -nodes -keyout wildcard.key -out wildcard.csr -subj "/CN=*.${DOMAIN}/C=DE/O=AAA_onemarcfifty/emailAddress=admin@${DOMAIN}"
openssl x509 -req -in wildcard.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out wildcard.crt -days 3650 -sha256 -extfile wildcard.cnf -extensions req_ext
cat wildcard.crt rootCA.crt >wildcard_fullchain.crt

# now the CSR and cert for the imap server
openssl req -newkey rsa:2048 -nodes -keyout imap.key -out imap.csr -subj "/CN=imap.${DOMAIN}/C=DE/O=AAA_onemarcfifty/emailAddress=admin@${DOMAIN}"
openssl x509 -req -in imap.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out imap.crt -days 3650 -sha256 -extfile imap.cnf -extensions req_ext
cat imap.crt rootCA.crt >imap_fullchain.crt

# copy the certificates over to the containers
for THECONTAINER in $CLIENTID $DOCKERID ; do
  pct exec $THECONTAINER -- mkdir -p /etc/certificates/${DOMAIN}
  for i in *.crt *.key ; do 
    pct push $THECONTAINER $i /etc/certificates/${DOMAIN}/${i} 
  done
done

# #########################################
echo -e "\n ##### configuring the containers \n"
# #########################################

# create a non-root user
pct exec $CLIENTID -- useradd -m -s /bin/bash -G sudo $NONROOTUSER
#pct exec $CLIENTID -- bash -c "echo -e '$NONROOTPASSWD\n$NONROOTPASSWD\n' | passwd $NONROOTUSER"
pct exec $CLIENTID -- bash -c "echo '$NONROOTUSER:$NONROOTPASSWD' | chpasswd"

# push dhcp settings to avoid routing over the ingress interface
pct push $CLIENTID exc-client/dhclient.conf /etc/dhcp/dhclient.conf
pct exec $CLIENTID -- systemctl restart networking

# push and execute the init script to the client
pct push $CLIENTID exc-client/init-router-script.sh /root/init-router-script.sh
pct push $CLIENTID exc-client/init-script.sh /root/init-script.sh
pct exec $CLIENTID -- bash /root/init-script.sh "$NONROOTUSER" "$DOMAIN" "$ROUTERIP"

# push and execute the init script to the docker host
pct push $DOCKERID exc-docker/init-script.sh /root/init-script.sh
pct exec $DOCKERID -- bash /root/init-script.sh "$NONROOTUSER" "$DOMAIN" 

echo -e "\n ############# DONE - Please reboot all VMs and CTs \n"
echo -e "\n ############# and then connect with RDP to the following IP address : \n"
pct exec $CLIENTID -- ip -br addr | grep eth0
