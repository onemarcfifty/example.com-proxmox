#!/bin/ash

# ################################
# the init script for the router 
# ################################

DOMAIN=$1

# add the domain to the dnsmasq settings
# and allow upstream RFC 1918 addresses
uci set dhcp.@dnsmasq[0].domainneeded='0'
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci set dhcp.@dnsmasq[0].local="/${DOMAIN}/"
uci set dhcp.@dnsmasq[0].domain="${DOMAIN}"
uci set dhcp.@dnsmasq[0].boguspriv='0'
uci commit

# add the mail relevant settings (Server CNAMEs and MX record)
if grep imap /etc/dnsmasq.conf ; then
  echo "dnsmasq Config seems to be there already"
else
(cat >>/etc/dnsmasq.conf) <<EOF
cname=imap,exc-Docker
cname=smtp,exc-Docker
cname=mail,exc-Docker
cname=imap.${DOMAIN},exc-Docker
cname=smtp.${DOMAIN},exc-Docker
cname=mail.${DOMAIN},exc-Docker
mx-host=${DOMAIN},mail.${DOMAIN},10
EOF
fi

# apply all changes
/etc/init.d/dnsmasq restart
