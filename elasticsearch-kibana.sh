#!/usr/bin/env bash

## Linode/SSH Security Settings
#<UDF name="username" label="The limited sudo user to be created for the Linode" default="">
#<UDF name="password" label="The password for the limited sudo user" example="s3cure_p4ssw0rd" default="">
#<UDF name="pubkey" label="The SSH Public Key that will be used to access the Linode" default="">
#<UDF name="disable_root" label="Disable password authentication over SSH?" oneOf="Yes,No" default="No">
#<UDF name="ds2_username" label="The user to post data from Akamai DataStream 2" default="ds2user">
#<UDF name="ds2_password" label="The password to post data from Akamai DataStream 2" default="">
#<UDF name="kibana_username" label="The user to login to Kibana" default="kbadmin">
#<UDF name="kibana_password" label="The password to login to Kibana (Default: kbpassword)" default="kbpassword">

## Enable logging
set -o pipefail
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

## Import the Bash StackScript Library
source <ssinclude StackScriptID=1>

## Import the OCA Helper Functions
source <ssinclude StackScriptID=401712>

## Run initial configuration tasks (DNS/SSH stuff, etc...)
source <ssinclude StackScriptID=666912>

## Update system & set hostname & basic security
set_hostname
apt_setup_update
ufw_install
ufw allow 5601/tcp
ufw allow 9200/tcp

## Time sync configuration
sed -i "s/^#NTP=/NTP=pool.ntp.org/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd

# Install Elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
apt-get install apt-transport-https
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
apt-get update
apt-get install elasticsearch
sed -z -i -e "s/xpack\.security\.http\.ssl:\n  enabled: true/xpack.security.http.ssl:\n  enabled: false/" /etc/elasticsearch/elasticsearch.yml

mkdir /etc/systemd/system/elasticsearch.service.d
echo -e "[Service]\nTimeoutStartSec=180" | sudo tee /etc/systemd/system/elasticsearch.service.d/startup-timeout.conf
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service

# Create a new index for Elasticsearch
ELASTIC_ADMIN_PASSWORD=`/usr/share/elasticsearch/bin/elasticsearch-reset-password -b -u elastic | grep 'New value' | sed 's/New value:\s*//'`
curl --cacert /etc/elasticsearch/certs/http_ca.crt -u elastic:$ELASTIC_ADMIN_PASSWORD -X PUT "http://localhost:9200/datastream2?pretty"

# Install Kibana
ELASTIC_KIBANA_PASSWORD=`/usr/share/elasticsearch/bin/elasticsearch-reset-password -b -u kibana_system | grep 'New value' | sed 's/New value:\s*//'`

apt-get install kibana
sed -i -e "s/#server\.host:.*/server.host: \"0.0.0.0\"/" /etc/kibana/kibana.yml
sed -i -e "s/#elasticsearch\.username:.*/elasticsearch.username: \"kibana_system\"/" /etc/kibana/kibana.yml
sed -i -e "s/#elasticsearch\.password:.*/elasticsearch.password: \"$ELASTIC_KIBANA_PASSWORD\"/" /etc/kibana/kibana.yml

systemctl daemon-reload
systemctl enable kibana.service
systemctl start kibana.service

# Create an Elasticsearch user to login to Kibana
curl --cacert /etc/elasticsearch/certs/http_ca.crt -u elastic:$ELASTIC_ADMIN_PASSWORD -X POST "http://localhost:9200/_security/user/$KIBANA_USERNAME" -H 'Content-Type: application/json' -d '{ "password" : "$KIBANA_PASSWORD", "roles": ["kibana_admin"] }'

# Create an Elasticsearch user to push logs from DataStream 2
curl --cacert /etc/elasticsearch/certs/http_ca.crt -u elastic:$ELASTIC_ADMIN_PASSWORD -X POST "http://localhost:9200/_security/role/ds2_writer" -H 'Content-Type: application/json' -d '{ "indices": [ { "names": "datastream2", "privileges": ["write"] } ] }'
curl --cacert /etc/elasticsearch/certs/http_ca.crt -u elastic:$ELASTIC_ADMIN_PASSWORD -X POST "http://localhost:9200/_security/user/$DS2_USERNAME" -H 'Content-Type: application/json' -d '{ "password" : "$DS2_PASSWORD", "roles": ["ds2_writer"] }'

wall "StackScripts is finished. Please check /var/log/stackscript.log"
