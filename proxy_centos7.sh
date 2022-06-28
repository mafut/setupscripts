#!/bin/bash

function setup_proxy(){
    # Initialize variables
    PASS=$1
    if [ -z "${PASS}" ];
    then
        echo "Can't get password"
        exit 1
    fi
    
    HOMENETWORK=$2
    if [ -z "${HOMENETWORK}" ];
    then
        echo "Can't get allowed host"
        exit 1
    fi
    
    # Stop Services at the first
    systemctl stop squid
    
    # yum update/upgrade
    yum clean all
    yum update
    
    # Install packages
    yum -y install squid
    yum -y install httpd-tools
    yum -y install bind-utils
    
    # Create .htpasswd
    htpasswd -b -c /etc/squid/.htpasswd proxy ${PASS}
    
    # [Proxy] Setup squid
    HOMEIP=$(getent hosts ${HOMENETWORK} | awk '{print $1}')
    CONFIG=/etc/squid/squid.conf
    cp -f ${CONFIG} ${CONFIG}.bak
    cat << EOF > ${CONFIG}
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
acl localnet src ${HOMEIP}/32

acl microsoft dstdomain .office.com .office.net .office365.com .live.com .windows.com .windows.net .microsoft.com .skype.com .microsoftonline.com .1drv.ms .sharepoint.com .sharepoint-df.com
acl apple dstdomain .apple.com .icloud.com .mzstatic.com
acl google dstdomain .google.com .googleapis.com
acl iphoneapp dstdomain .slack.com .uber.com .amazon.com .amazone.co.jp

acl SSL_ports port 443
acl Safe_ports port 80 # http
acl Safe_ports port 443 # https
acl Safe_ports port 25 # exchange smpt
acl Safe_ports port 587 # exchange smpt
acl Safe_ports port 143 # exchange imap4
acl Safe_ports port 993 # exchange imap4
acl Safe_ports port 995 # exchange pop3
acl Safe_ports port 5223 # Apple push
acl Safe_ports port 1025-65535 # unregistered ports

acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

http_access allow microsoft
http_access allow apple
http_access allow google
http_access allow iphoneapp
http_access allow localnet
http_access allow localhost

http_port 8080

coredump_dir /var/spool/squid

refresh_pattern ^ftp:               1440    20% 10080
refresh_pattern ^gopher:            1440    0%  1440
refresh_pattern -i (/cgi-bin/|\?)   0       0%  0
refresh_pattern .                   0       20% 4320

forwarded_for off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all

visible_hostname unknown

auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/.htpasswd
auth_param basic children 5
auth_param basic realm Squid Basic Authentication
auth_param basic credentialsttl 24 hours
auth_param basic casesensitive off
acl password proxy_auth REQUIRED
http_access allow password
http_access deny all
EOF
    
    # Add Auto startup and Start service
    systemctl enable squid
    systemctl start squid
}

function setup_vpn(){
    # Initialize variables
    PASS=$1
    if [ -z "${PASS}" ];
    then
        echo "Can't get password"
        exit 1
    fi
    
    # Stop Services at the first
    systemctl stop pptpd
    
    # yum update/upgrade
    yum clean all
    yum update
    
    # Install packages
    yum -y install ppp pptpd
    
    # [vpn] Setup PPTP
    CONFIG=/etc/pptpd.conf
    cp -f ${CONFIG} ${CONFIG}.bak
    cat << EOF > ${CONFIG}
option /etc/ppp/pptpd-options
localip 192.169.1.1
remoteip 192.168.1.100-200
EOF
    
    CONFIG=/etc/ppp/pptpd-options
    cp -f ${CONFIG} ${CONFIG}.bak
    cat << EOF > ${CONFIG}
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd

ms-dns 8.8.8.8
ms-dns 8.8.4.4

mtu 1400
EOF
    
    CONFIG=/etc/ppp/chap-secrets
    cp -f ${CONFIG} ${CONFIG}.bak
    cat << EOF > ${CONFIG}
vpn pptpd "${PASS}" *
EOF
    
    CONFIG=/usr/lib/sysctl.d/50-default.conf
    cp -f ${CONFIG} ${CONFIG}.bak
    if ! grep -q 'net.ipv4.ip_forward' ${CONFIG};
    then
        cat << EOF >> ${CONFIG}
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
EOF
    fi
    sysctl -p
    
    # Add Auto startup and Start service
    systemctl enable pptpd
    systemctl start pptpd
}

if [ $# = 3 ] && [ $1 = "proxy" ];
then
    setup_proxy $2 $3
    exit 0
fi

if [ $# = 2 ] && [ $1 = "vpn" ];
then
    setup_vpn $2
    exit 0
fi

cat << EOF
[Usage]
setup_centos7.sh proxy [password] [allowed host]
setup_centos7.sh vpn [password]
EOF
exit 0
