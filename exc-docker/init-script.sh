#!/bin/bash

NONROOTUSER=$1
DOMAIN=$2

# in this container we install Docker with Portainer and Portainer-Agent

sed -i s/^#\ en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/ /etc/locale.gen
locale-gen
apt update
apt -y install ca-certificates curl gnupg lsb-release sudo git

# let's get the official Docker because Debian Docker does not run in unprivileged LXC 
# Containers as of 2022/2023

mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 

# Portainer does not seem to honor the --tlscacert flag correctly. That will
# become apparent when you try to do OIDC SSO with self-signed certificates or the like.
# as a workaround, we install the Root CA on the Docker host and later mount the modified 
# /etc/ssl/certs/ca-certificates.crt to the Container.

# we copy the root CA into the openssl cert folder
cp /etc/certificates/${DOMAIN}/rootCA.crt /etc/ssl/certs
# create the hash link
ln -s /etc/ssl/certs/rootCA.crt /etc/ssl/certs/`openssl x509 -hash -noout -in rootCA.crt`.0
# this will update the /etc/ssl/certs/ca-certificates.crt
update-ca-certificates

# now we can install portainer
docker pull portainer/portainer-ce:latest
docker run -d -p 9000:9000 -p 9443:9443 \
       --name=portainer \
       --restart=always \
       -v /var/run/docker.sock:/var/run/docker.sock \
       -v portainer_data:/data \
       -v /etc/certificates/${DOMAIN}:/certs \
       -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt \
       portainer/portainer-ce:latest \
       --sslcert /certs/wildcard_fullchain.crt \
       --sslkey /certs/wildcard.key \
       --tlscacert /certs/rootCA.crt
# little tip: in order to debug portainer behavior, add --log-level=DEBUG

# let's add portainer agent as well in case you already have an existing portainer somewhere
docker run -d -p 9001:9001 \
        --name portainer_agent \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /var/lib/docker/volumes:/var/lib/docker/volumes \
        portainer/agent:latest

# let's get the mail server
git clone https://github.com/onemarcfifty/docker-imap-devel.git
cd docker-imap-devel

# stop and disable local postfix
systemctl stop postfix
systemctl disable postfix

# build and create the container
docker compose build
docker compose create

# copy certificates to the docker cert volume
docker cp /etc/certificates/${DOMAIN}/imap_fullchain.crt imap:/etc/ssl/certs/ssl-cert-imap.pem
docker cp /etc/certificates/${DOMAIN}/imap.key imap:/etc/ssl/private/ssl-cert-imap.key
docker cp /etc/certificates/${DOMAIN}/rootCA.crt imap:/etc/ssl/certs/rootCA.pem

# bring up the mail server
docker compose up -d

# it will fail to start on the first attempt but should restart automatically
sleep 10

# just fix the certificate location for postfix
docker exec imap postconf -e smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-imap.pem
docker exec imap postconf -e smtpd_tls_key_file=/etc/ssl/private/ssl-cert-imap.key 
docker exec imap postconf -e smtp_tls_CApath=/etc/ssl/certs/rootCA.pem
docker exec imap /etc/init.d/postfix reload

# last but not least let's enable root ssh access with username and password.
# that's not secure for production environments but should be helpful here
# in order to ssh into the docker host if ever we need to copy the certificates
# for example. The host is not reachable from the outside world anyhow.
sed -i s/\#PermitRootLogin\ prohibit-password$/PermitRootLogin\ yes/ /etc/ssh/sshd_config
systemctl restart sshd