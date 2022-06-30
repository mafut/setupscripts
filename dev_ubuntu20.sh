#!/bin/bash

# Initialize variables
USERNAME=$SUDO_USER
APACHE_USER=www-data
APACHE_LOG=/var/log/apache2
APACHE_DOCPATH=$1
APACHE_PORT=$3
PHP_VER=7.4
CODESERVER_VER=4.4.0
CODESERVER_PASS=$2
CODESERVER_PORT=$4
CERT_PATH=$5
MYSQL_REPO=mysql-apt-config_0.8.22-1_all.deb

if [ -z "${USERNAME}" ];
then
    echo "Can't get User Name"
    exit 1
fi

if [ -z "${APACHE_PORT}" ];
then
    APACHE_PORT=8081
fi

if [ -z "${CODESERVER_PORT}" ];
then
    CODESERVER_PORT=8082
fi

if [ -z "${CERT_PATH}" ];
then
    CERT_PATH=$(cd $(dirname $0)/cert;pwd)
fi

if [ -z "${APACHE_DOCPATH}" ] && [ -z "${CODESERVER_PASS}" ];
then
    echo "Usage: this_script.sh [Apache Doc Path] [Code-Server Password] [Apache Port=8081] [Code-Server Port=8082] [Cert Path=setupscript/cert]"
    exit 1
fi

# Trim a trailing slash
APACHE_DOCPATH=${APACHE_DOCPATH%/}
CERT_PATH=${CERT_PATH%/}

# Stop Services at the first
systemctl disable --now nginx
systemctl disable --now apache2
systemctl disable --now mysql
systemctl disable --now code-server
systemctl disable --now code-server@${USERNAME}

# apt-get update/upgrade
# add-apt-repository ppa:ondrej/apache2 -y
apt-get -y --force-yes update
apt-get -y --force-yes upgrade

# Install packages
apt-get -y --force-yes install wget zip unzip
apt-get -y --force-yes install certbot python3
apt-get -y --force-yes install apache2 php php-gd php-mbstring php-mysql php-apcu php-soap libapache2-mod-php composer
apt-get -y --force-yes install ufw nginx
apt-get -y --force-yes autoremove
a2enmod authz_groupfile
a2enmod headers
a2enmod rewrite
a2ensite ${USERNAME}

a2dismod ssl
a2dismod proxy
a2dismod proxy_http
a2dismod proxy_wstunnel
a2dissite default-ssl

# [Security] Skip password when sudo. The format is "${USERNAME} ALL=NOPASSWD: ALL"
if ! grep -q ${USERNAME} /etc/sudoers;
then
    echo ${USERNAME} ALL=NOPASSWD: ALL >> /etc/sudoers
fi

# [Security] Setup Firewall
ufw disable
ufw --force reset
ufw default deny
ufw allow 22
ufw limit 22
ufw allow 80
ufw allow 443
ufw allow 1723      # PPTP
ufw allow 8080      # Squid
ufw --force enable


# [Code-Server] Install
if [ ! -e ./code-server_${CODESERVER_VER}_amd64.deb ]; then
    curl -fOL https://github.com/coder/code-server/releases/download/v${CODESERVER_VER}/code-server_${CODESERVER_VER}_amd64.deb
    dpkg -i ./code-server_${CODESERVER_VER}_amd64.deb
fi

# [Code-Server] Reset Permission
mkdir -p /home/${USERNAME}/.local/share/code-server
chown -R ${USERNAME} /home/${USERNAME}/.local/share/code-server
chgrp -R ${USERNAME} /home/${USERNAME}/.local/share/code-server
find /home/${USERNAME}/.local/share/code-server -type d -exec chmod 755 {} \;
find /home/${USERNAME}/.local/share/code-server -type f -exec chmod 644 {} \;

# [Code-Server] Config
CONFIG=/etc/systemd/system/code-server.service
cat << EOF > ${CONFIG}
[Unit]
Description=code-server
After=apache2.service

[Service]
Type=simple
User=${USERNAME}
WorkingDirectory=/home/${USERNAME}
Restart=always
RestartSec=10

ExecStart=/user/bin/code-server --host 127.0.0.1 --user-data-dir /home/${USERNAME}/.local/share/code-server
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
EOF

CONFIG=/home/${USERNAME}/.config/code-server/config.yaml
cat << EOF > ${CONFIG}
bind-addr: 127.0.0.1:${CODESERVER_PORT}
auth: password
password: ${CODESERVER_PASS}
cert: false
user-data-dir: /home/${USERNAME}/.local/share/code-server
log: debug
EOF


# [MySQL] Install
if [ ! -e ${MYSQL_REPO} ]; then
    curl -fOL https://dev.mysql.com/get/${MYSQL_REPO}
    dpkg -i ./${MYSQL_REPO}
    apt-get -y --force-yes install mysql-server
fi

# [MySQL] /etc/mysql/my.cnf
CONFIG=/etc/mysql/mysql.conf.d/mysqld.cnf
cp -f ${CONFIG} ${CONFIG}.bak
cat << EOF > ${CONFIG}
[mysqld]
pid-file  = /var/run/mysqld/mysqld.pid
socket    = /var/run/mysqld/mysqld.sock
datadir   = /var/lib/mysql
log-error = /var/log/mysql/error.log
bind-address = 127.0.0.1
symbolic-links = 0
explicit_defaults_for_timestamp = 0
sql-mode = "NO_ENGINE_SUBSTITUTION"
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
default-storage-engine=innodb
default_password_lifetime = 0
innodb_file_per_table = 1

[mysql]
auto-rehash
default-character-set = utf8mb4

[mysqldump]
default-character-set = utf8mb4
EOF

# [MySQL] Resolve warning at start
dpkg-divert --local --rename --add /sbin/initctl
if [ ! -e /sbin/initctl ];
then
    ln -s /bin/true /sbin/initctl
fi
usermod -d /var/lib/mysql/ mysql


# [Apache] Reset Permission: User(6)/UserGroup(4)/Other(4)
chown -R ${USERNAME} ${APACHE_DOCPATH}/
chgrp -R ${USERNAME} ${APACHE_DOCPATH}/
find ${APACHE_DOCPATH}/ -type d -exec chmod 755 {} \;
find ${APACHE_DOCPATH}/ -type f -exec chmod 644 {} \;

mkdir -p /var/www/html/setting/
chown -R ${USERNAME} /var/www/html/setting/
chgrp -R ${USERNAME} /var/www/html/setting/
find /var/www/html/setting/ -type d -exec chmod 755 {} \;
find /var/www/html/setting/ -type f -exec chmod 644 {} \;

mkdir -p ${APACHE_LOG}
chown -R ${USERNAME} ${APACHE_LOG}
chgrp -R ${USERNAME} ${APACHE_LOG}
find ${APACHE_LOG} -type d -exec chmod 755 {} \;
find ${APACHE_LOG} -type f -exec chmod 644 {} \;

# [Apache] User to Apache
chown -R ${APACHE_USER} ${APACHE_DOCPATH}/application/logs/
chown -R ${APACHE_USER} ${APACHE_DOCPATH}/application/cache/
chown -R ${APACHE_USER} ${APACHE_DOCPATH}/setting/
chown -R ${APACHE_USER} /var/www/html/setting/
chown -R ${APACHE_USER} ${APACHE_LOG}

# [Apache] Configure Permission
find /var/www/html/setting/ -type f -exec chmod 600 {} \;
find ${APACHE_DOCPATH}/setting/ -type f -exec chmod 600 {} \;
find ${APACHE_DOCPATH}/ -name .htaccess -exec chmod 644 {} \;
find ${APACHE_DOCPATH}/ -name index.html -exec chmod 644 {} \;
find ${APACHE_DOCPATH}/setup/ -name \*.sh -exec chmod 755 {} \;

# [Apache] Configure http
CONFIG=/etc/apache2/sites-available/000-default.conf
cat << EOF > ${CONFIG}
AcceptFilter http none
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName localhost:80

    LogLevel warn
    ErrorLog ${APACHE_LOG}/error.log
    CustomLog ${APACHE_LOG}/access.log combined

    DocumentRoot /var/www/html
    <Directory /var/www/html>
        Options All
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/000-default.conf
ln -s /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-enabled/000-default.conf

CONFIG=/etc/apache2/sites-available/${USERNAME}.conf
cat << EOF > ${CONFIG}
AcceptFilter http none
Listen ${APACHE_PORT}
<VirtualHost *:${APACHE_PORT}>
    ServerAdmin webmaster@localhost
    ServerName localhost:${APACHE_PORT}

    LogLevel warn
    ErrorLog ${APACHE_LOG}/error.log
    CustomLog ${APACHE_LOG}/access.log combined

    DocumentRoot ${APACHE_DOCPATH}
    <Directory ${APACHE_DOCPATH}>
        Options All
        AllowOverride All
        Require all granted
    </Directory>

    Alias /application/views ${APACHE_DOCPATH}/application/views
    <Directory ${APACHE_DOCPATH}/application/views>
        Options All
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/${USERNAME}.conf
ln -s /etc/apache2/sites-available/${USERNAME}.conf /etc/apache2/sites-enabled/${USERNAME}.conf


# [Php] Set display_errors, display_startup_errors as ON
CONFIG=/etc/php/${PHP_VER}/apache2/php.ini
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|display_errors = Off|display_errors = On|g\" ${CONFIG}.bak > ${CONFIG}"
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|display_startup_errors = Off|display_startup_errors = On|g\" ${CONFIG}.bak > ${CONFIG}"
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|;extension=php_soap.dll|extension=php_soap.dll|g\" ${CONFIG}.bak > ${CONFIG}"


# [Nginx] Configure https
rm -f /etc/nginx/sites-enabled/default

CONFIG=/etc/nginx/sites-available/${USERNAME}
cat << EOF > ${CONFIG}
server {
    listen 443 ssl;
    server_name ${USERNAME}.*;

    ssl_certificate ${CERT_PATH}/fullchain.pem;
    ssl_certificate_key ${CERT_PATH}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${APACHE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Accept-Encoding gzip;
    }

    location /vscode/ {
        proxy_pass http://127.0.0.1:${CODESERVER_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/${USERNAME}
ln -s /etc/nginx/sites-available/${USERNAME} /etc/nginx/sites-enabled/${USERNAME}

# Add auto-start and start services
systemctl enable --now nginx
systemctl enable --now apache2
systemctl enable --now mysql
systemctl enable --now code-server@${USERNAME}
loginctl enable-linger ${USERNAME}


# [Cron] Schedule to pull
CONFIG=${APACHE_DOCPATH}/setting/crontab.bak
cat << EOF > ${CONFIG}
# */5 * * * * /bin/sh -c 'cd ${APACHE_DOCPATH} && /usr/bin/git fetch --all && /usr/bin/git checkout . && /usr/bin/git clean -df && /usr/bin/git reset --hard origin/master && /usr/bin/git pull origin master'
*/5 * * * * /bin/sh -c 'cd ${APACHE_DOCPATH} && /usr/bin/git fetch --all && /usr/bin/git pull origin master'
EOF
crontab -u ${USERNAME} ${APACHE_DOCPATH}/setting/crontab.bak
