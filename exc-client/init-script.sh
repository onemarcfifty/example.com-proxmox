#!/bin/bash

# ###########################
# init script for the client
# ###########################

NONROOTUSER=$1
DOMAIN=$2
ROUTERIP=$3

# first let's copy the router init script to the router and execute it
scp -o StrictHostKeyChecking=no /root/init-router-script.sh root@${ROUTERIP}:/root
ssh root@${ROUTERIP} ash init-router-script.sh $DOMAIN

# we'll install a fully-blown graphical environment into that container with MATE
# (feel free to install xfce instead if you want)
# plus web browser (Firefox) and e-mail client (Thunderbird)
# as well as xrdp for remote access

sed -i s/^#\ en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/ /etc/locale.gen
locale-gen
apt update
apt -y install mate-desktop-environment wget gpg curl sudo firefox-esr thunderbird xorg xorgxrdp xrdp git libnss3-tools openssl filezilla

# Install vs code 
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg
apt update
apt -y install code 

USERHOME=$(grep -i ^$NONROOTUSER: /etc/passwd | cut -d ":" -f 6)

# add the certificates to the Firefox profile policy
(cat >/usr/lib/firefox-esr/distribution/policies.json) <<EOF
{
    "policies": {
        "Certificates": {
            "Install": [
                "/etc/certificates/${DOMAIN}/rootCA.crt"
            ]
        }
    }
}
EOF

# copy them to the Thunderbird installation as well
mkdir -p /usr/lib/thunderbird/distribution
cp /usr/lib/firefox-esr/distribution/policies.json /usr/lib/thunderbird/distribution/


