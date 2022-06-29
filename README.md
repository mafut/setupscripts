# Proxy (squid) and VPN (pptp) setup
### proxy_centos7.sh
### proxy_ubuntu18.sh

This is just shell script to setup proxy and vpn on cloud server (I'm using Azure). Main target user is who lives outside of Japan and expects to browse restricted sites and watch ondemand TV (e.g. TVer). Even non restricted site would have better performance by avoiding unnecessary routing. 

### Notes
* Watch ondemand TV (except Netflix and hulu. Amazon is not tested yet). TVer and Gyao work.
* Z-kai online study with better streaming performance.


# PHP with Code-Server
### dev_ubuntu18.sh
### dev_ubuntu20.sh

This script setups Apache-PHP-MySQL site with Code-Server. This also supports multi-user and expects the following as the result.

Url | What you can
-|-
http://[user].your_domain/ | Apache default. This is used for certbot as well.
https://[user].your_domain/ | Your PHP-MySQL site.
https://[user].your_domain/vscode/ | Code-Server to develop your PHP-MySQL site.

## Quick Steps
1. Create new user and login
    1. sudo adduser [user]
    2. su [user]
2. Configure SSH
    1. ssh-keygen
    2. Register id_rsa.pub to github
    3. (Option) Add yubikey's public cert to authorized_keys
3. Get the latest source
    * git clone git@github.com:mafut/setupscripts.git
4. Setup a site with self-signed cert
    * sudo ./dev_ubuntu20.sh [your_site_folder] password 8081 8082
5. Issue a certificate
    * sudo certbot certonly --agree-tos --webroot -w /var/www/html/ -d [user].your_domain
6. Setup with real cert
    * sudo ./dev_ubuntu20.sh [your_site_folder] password 8081 8082 /etc/letsencrypt/live/[user].[your_domain]
