#!/usr/bin/env bash

## Linode/SSH Security Settings
#<UDF name="email" label="Email address required for issuing an SSL Certificate through Let's Encrypt">
#<UDF name="os_access_key" label="Access Key of Linode Object Storage">
#<UDF name="os_secret_key" label="Secret Key of Linode Object Storage">
#<UDF name="os_region" label="Region of Linode Object Storage" oneOf="us-iad-1,us-east-1,eu-central-1,ap-south-1,us-southeast-1">
#<UDF name="os_bucketname" label="Bucket Name of Linode Object Storage">
#<UDF name="username" label="The limited sudo user to be created for the Linode" default="">
#<UDF name="password" label="The password for the limited sudo user" example="s3cure_p4ssw0rd" default="">
#<UDF name="pubkey" label="The SSH Public Key that will be used to access the Linode" default="">
#<UDF name="disable_root" label="Disable password authentication over SSH?" oneOf="Yes,No" default="No">

## Enable logging
set -o pipefail
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

## Import the Bash StackScript Library
source <ssinclude StackScriptID=1>

## Import the OCA Helper Functions
source <ssinclude StackScriptID=401712>

## Run initial configuration tasks (DNS/SSH stuff, etc...)
source <ssinclude StackScriptID=666912>

## OS fine-tuning (https://docs.fluentd.org/installation/before-install)
cat >> /etc/sysctl.conf <<EOF
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
net.ipv4.tcp_max_syn_backlog = 8096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.ip_local_reserved_ports = 24224
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
sysctl -p

cat >> /etc/security/limits.conf <<EOF
root soft nofile 65536
root hard nofile 65536
* soft nofile 65536
* hard nofile 65536
EOF

## Update system & set hostname & basic security
set_hostname
apt_setup_update
ufw_install
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 8888/tcp

## Time sync configuration
sed -i "s/^#NTP=/NTP=pool.ntp.org/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd

# Install Certbot
snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# Issue an SSL server certificate
certbot certonly -n --standalone --agree-tos -d `hostname` --email "$EMAIL"
chmod -R 755 /etc/letsencrypt/archive
chmod -R 755 /etc/letsencrypt/live

# Issue an SSL client certificate for mTLS between DataStream 2 and Fluentd
mkdir -p /etc/td-agent/ssl
openssl genrsa 2048 > /etc/ssl/private/ca-fluentd-key.pem
openssl req -new -x509 -nodes -days 365000 -key /etc/ssl/private/ca-fluentd-key.pem -out /etc/ssl/certs/ca-fluentd-cert.pem -subj "/CN=CA for Fluentd"
openssl req -newkey rsa:2048 -nodes -days 365000 -keyout /etc/td-agent/ssl/ds2-client-key.pem -out /etc/td-agent/ssl/ds2-client-req.pem -subj "/CN=DataStream 2 Client"
openssl x509 -req -days 365000 -set_serial 01 -in /etc/td-agent/ssl/ds2-client-req.pem -out /etc/td-agent/ssl/ds2-client-cert.pem -CA /etc/ssl/certs/ca-fluentd-cert.pem -CAkey /etc/ssl/private/ca-fluentd-key.pem
rm /etc/td-agent/ssl/ds2-client-req.pem

# Install Fluentd (td-agent)
curl -fsSL https://toolbelt.treasuredata.com/sh/install-ubuntu-jammy-td-agent4.sh | sh

# Setup and start Fluentd
cat > /etc/td-agent/td-agent.conf <<EOF
<source>
  @type http
  port 8888
  bind 0.0.0.0
  keepalive_timeout 305s

  <transport tls>
    version TLSv1_2
    ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384
    insecure false

    # For Cert signed by public CA
    cert_path /etc/letsencrypt/live/`hostname`/fullchain.pem
    private_key_path /etc/letsencrypt/live/`hostname`/privkey.pem

    client_cert_auth true
    ca_path /etc/ssl/certs/ca-fluentd-cert.pem
  </transport>

  <parse>
    @type none
  </parse>
</source>

<label @FLUENT_LOG>
  <match fluent.*>
    @type stdout
  </match>
</label>

<match **>
  @type s3
  format single_value

  aws_key_id $OS_ACCESS_KEY
  aws_sec_key $OS_SECRET_KEY
  s3_bucket $OS_BUCKETNAME
  s3_endpoint https://$OS_REGION.linodeobjects.com
  s3_region $OS_REGION
  path logs/
  <buffer time>
    @type file
    compress gzip
    chunk_limit_size 1g
    path /opt/td-agent/buffer
    timekey 60m
    timekey_wait 2m
    timekey_use_utc true # use utc
  </buffer>
</match>
EOF

mkdir -p /opt/td-agent/buffer
chown td-agent:td-agent /opt/td-agent/buffer
chmod 700 /opt/td-agent/buffer

systemctl enable td-agent

# Configure Login Message
echo "Maintainer: Hideki Okamoto @ Akamai Technologies" > /etc/motd
echo "##############################################################################" >> /etc/motd
echo "You can find a client certificate for mTLS between DataStream 2 and Fluentd in /etc/td-agent/ssl/" >> /etc/motd
echo "##############################################################################" >> /etc/motd

# Upgrade APT packages and reboot
apt -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
reboot