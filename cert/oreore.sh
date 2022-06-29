#!/bin/bash
sudo openssl req -new -nodes -newkey rsa:4096 -x509 -sha256 -keyout privkey.pem -out fullchain.pem -days 3650 -subj /CN=localhost -config openssl.cnf
