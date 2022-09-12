#!/usr/bin/env bash

## Linode/SSH Security Settings
#<UDF name="username" label="The limited sudo user to be created for the Linode" default="">
#<UDF name="password" label="The password for the limited sudo user" example="s3cure_p4ssw0rd" default="">
#<UDF name="pubkey" label="The SSH Public Key that will be used to access the Linode" default="">
#<UDF name="disable_root" label="Disable password authentication over SSH?" oneOf="Yes,No" default="No">
#<UDF name="grafana_username" label="The user to be created for Grafana dashboard" default="admin">
#<UDF name="grafana_password" label="The password to login Grafana dashboard (Default: admin)" example="an0th3r_s3cure_p4ssw0rd" default="admin">

## Enable logging
set -o pipefail
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

## Import the Bash StackScript Library
source <ssinclude StackScriptID=1>

## Import the OCA Helper Functions
source <ssinclude StackScriptID=401712>

## Run initial configuration tasks (DNS/SSH stuff, etc...)
source <ssinclude StackScriptID=666912>

## OS fine-tuning (https://k6.io/docs/testing-guides/running-large-tests/)
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_timestamps=1
EOF
sysctl -p

cat >> /etc/security/limits.conf <<EOF
*    soft nofile 250000
*    hard nofile 250000
root soft nofile 250000
root hard nofile 250000
EOF

## Update system & set hostname & basic security
set_hostname
apt_setup_update
ufw_install
ufw allow 3000/tcp

## Time sync configuration
sed -i "s/^#NTP=/NTP=pool.ntp.org/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd

## Install InfluxDB
apt install influxdb -y
sed -i -e "s/# max-body-size = 25000000/max-body-size = 100000000/g" /etc/influxdb/influxdb.conf
systemctl restart influxdb

## Install Grafana
apt install -y apt-transport-https
apt install -y software-properties-common wget
wget -q -O /usr/share/keyrings/grafana.key https://packages.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
apt update
apt install grafana -y

sed -i -e "s/;admin_user = \(.*\)/admin_user = $GRAFANA_USERNAME/g" /etc/grafana/grafana.ini
sed -i -e "s/;admin_password = \(.*\)/admin_password = $GRAFANA_PASSWORD/g" /etc/grafana/grafana.ini
sed -i -e "s/;provisioning = conf\/provisioning/provisioning = conf\/provisioning/g" /etc/grafana/grafana.ini

cat > /usr/share/grafana/conf/provisioning/datasources/influxdb.yaml <<EOF
apiVersion: 1

datasources:
  # <string, required> name of the datasource. Required
  - name: InfluxDB
    # <string, required> datasource type. Required
    type: influxdb
    # <string, required> access mode. proxy or direct (Server or Browser in the UI). Required
    access: proxy
    # <string> custom UID which can be used to reference this datasource in other parts of the configuration, if not specified will be generated automatically
    uid: P951FEA4DE68E13C5
    # <string> url
    url: http://localhost:8086
    # <string> database name, if used
    database: myk6db
    # <bool> mark as default datasource. Max one per org
    isDefault: true
    # <bool> allow users to edit datasources from the UI.
    editable: true
EOF

cat > /usr/share/grafana/conf/provisioning/dashboards/k6.yaml <<EOF
apiVersion: 1

providers:
  # <string> an unique provider name. Required
  - name: 'InfluxDB'
    # <string> provider type. Default to 'file'
    type: file
    # <bool> disable dashboard deletion
    disableDeletion: false
    # <bool> allow updating provisioned dashboards from the UI
    allowUiUpdates: true
    options:
      # <string, required> path to dashboard files on disk. Required when using the 'file' type
      path: /var/lib/grafana/dashboards
EOF

mkdir -p /var/lib/grafana/dashboards/
cat > /var/lib/grafana/dashboards/k6.json <<EOF
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "grafana",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": [],
          "type": "dashboard"
        },
        "type": "dashboard"
      }
    ]
  },
  "description": "A dashboard for visualizing results from the k6.io load testing tool, using the InfluxDB exporter",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "gnetId": 2587,
  "graphTooltip": 2,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "collapsed": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 18,
      "panels": [],
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "refId": "A"
        }
      ],
      "title": "Dashboard Row",
      "type": "row"
    },
    {
      "aliasColors": {},
      "bars": true,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 0,
        "y": 1
      },
      "hiddenSeries": false,
      "id": 1,
      "interval": ">1s",
      "legend": {
        "alignAsTable": true,
        "avg": false,
        "current": false,
        "max": true,
        "min": true,
        "show": true,
        "total": false,
        "values": true
      },
      "lines": false,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.1.2",
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "alias": "Active VUs",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "vus",
          "orderByTime": "ASC",
          "policy": "default",
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "Virtual Users",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": true
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "aliasColors": {},
      "bars": true,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 6,
        "y": 1
      },
      "hiddenSeries": false,
      "id": 17,
      "interval": "1s",
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "max": true,
        "min": false,
        "rightSide": false,
        "show": true,
        "total": false,
        "values": true
      },
      "lines": false,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.1.2",
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "alias": "Requests per Second",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "measurement": "http_reqs",
          "orderByTime": "ASC",
          "policy": "default",
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "sum"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "Requests per Second",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": true
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "aliasColors": {},
      "bars": true,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 12,
        "y": 1
      },
      "hiddenSeries": false,
      "id": 7,
      "interval": "1s",
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": false,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.1.2",
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "Num Errors",
          "color": "#BF1B00"
        }
      ],
      "spaceLength": 10,
      "stack": true,
      "steppedLine": false,
      "targets": [
        {
          "alias": "Num Errors",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "errors",
          "orderByTime": "ASC",
          "policy": "default",
          "refId": "C",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "count"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "Errors Per Second",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": true
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "aliasColors": {},
      "bars": true,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 7,
        "w": 6,
        "x": 18,
        "y": 1
      },
      "hiddenSeries": false,
      "id": 10,
      "interval": ">1s",
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": false,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.1.2",
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "Num Errors",
          "color": "#BF1B00"
        }
      ],
      "spaceLength": 10,
      "stack": true,
      "steppedLine": false,
      "targets": [
        {
          "alias": "\$tag_check",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "check"
              ],
              "type": "tag"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "checks",
          "orderByTime": "ASC",
          "policy": "default",
          "refId": "C",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "sum"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "Checks Per Second",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "none",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": true
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "collapsed": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 8
      },
      "id": 19,
      "panels": [],
      "repeat": "Measurement",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "refId": "A"
        }
      ],
      "title": "\$Measurement",
      "type": "row"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 0,
        "y": 9
      },
      "id": 11,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT mean(\"value\") FROM \$Measurement WHERE \$timeFilter ",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (mean)",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 4,
        "y": 9
      },
      "id": 14,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT max(\"value\") FROM \$Measurement WHERE \$timeFilter",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (max)",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 8,
        "y": 9
      },
      "id": 15,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT median(\"value\") FROM \$Measurement WHERE \$timeFilter",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (med)",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 12,
        "y": 9
      },
      "id": 16,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT min(\"value\") FROM \$Measurement WHERE \$timeFilter and value > 0",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (min)",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 16,
        "y": 9
      },
      "id": 12,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT percentile(\"value\", 90) FROM \$Measurement WHERE \$timeFilter",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (p90)",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "decimals": 2,
          "mappings": [
            {
              "options": {
                "match": "null",
                "result": {
                  "text": "N/A"
                }
              },
              "type": "special"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "ms"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 3,
        "w": 4,
        "x": 20,
        "y": 9
      },
      "id": 13,
      "links": [],
      "maxDataPoints": 100,
      "options": {
        "colorMode": "none",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT percentile(\"value\", 95) FROM \$Measurement WHERE \$timeFilter ",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (p95)",
      "type": "stat"
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "description": "Grouped by 1 sec intervals",
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 7,
        "w": 12,
        "x": 0,
        "y": 12
      },
      "height": "250px",
      "hiddenSeries": false,
      "id": 5,
      "interval": ">1s",
      "legend": {
        "alignAsTable": false,
        "avg": false,
        "current": false,
        "max": false,
        "min": false,
        "show": true,
        "total": false,
        "values": false
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.1.2",
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "alias": "max",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "/^\$Measurement\$/",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT max(\"value\") FROM /^\$Measurement\$/ WHERE \$timeFilter and value > 0 GROUP BY time(\$__interval) fill(none)",
          "rawQuery": true,
          "refId": "C",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "max"
              }
            ]
          ],
          "tags": []
        },
        {
          "alias": "p95",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "/^\$Measurement\$/",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT percentile(\"value\", 95) FROM /^\$Measurement\$/ WHERE \$timeFilter and value > 0 GROUP BY time(\$__interval) fill(none)",
          "rawQuery": true,
          "refId": "D",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [
                  95
                ],
                "type": "percentile"
              }
            ]
          ],
          "tags": []
        },
        {
          "alias": "p90",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "/^\$Measurement\$/",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT percentile(\"value\", 90) FROM /^\$Measurement\$/ WHERE \$timeFilter and value > 0 GROUP BY time(\$__interval) fill(none)",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [
                  "90"
                ],
                "type": "percentile"
              }
            ]
          ],
          "tags": []
        },
        {
          "alias": "min",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "none"
              ],
              "type": "fill"
            }
          ],
          "measurement": "/^\$Measurement\$/",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT min(\"value\") FROM /^\$Measurement\$/ WHERE \$timeFilter and value > 0 GROUP BY time(\$__interval) fill(none)",
          "rawQuery": true,
          "refId": "E",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "min"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "\$Measurement (over time)",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "ms",
          "logBase": 2,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": true
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "cards": {},
      "color": {
        "cardColor": "rgb(0, 234, 255)",
        "colorScale": "sqrt",
        "colorScheme": "interpolateRdYlGn",
        "exponent": 0.5,
        "mode": "spectrum"
      },
      "dataFormat": "timeseries",
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "custom": {
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "scaleDistribution": {
              "type": "linear"
            }
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 7,
        "w": 12,
        "x": 12,
        "y": 12
      },
      "heatmap": {},
      "height": "250px",
      "highlightCards": true,
      "id": 8,
      "interval": ">1s",
      "links": [],
      "options": {
        "calculate": true,
        "calculation": {
          "yBuckets": {
            "mode": "count",
            "scale": {
              "log": 2,
              "type": "log"
            }
          }
        },
        "cellGap": 2,
        "cellValues": {},
        "color": {
          "exponent": 0.5,
          "fill": "rgb(0, 234, 255)",
          "mode": "scheme",
          "scale": "exponential",
          "scheme": "RdYlGn",
          "steps": 128
        },
        "exemplars": {
          "color": "rgba(255,0,255,0.7)"
        },
        "filterValues": {
          "le": 1e-9
        },
        "legend": {
          "show": false
        },
        "rowsFrame": {
          "layout": "auto"
        },
        "showValue": "never",
        "tooltip": {
          "show": true,
          "yHistogram": true
        },
        "yAxis": {
          "axisPlacement": "left",
          "reverse": false,
          "unit": "ms"
        }
      },
      "pluginVersion": "9.1.2",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "dsType": "influxdb",
          "groupBy": [
            {
              "params": [
                "\$__interval"
              ],
              "type": "time"
            },
            {
              "params": [
                "null"
              ],
              "type": "fill"
            }
          ],
          "measurement": "http_req_duration",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT \"value\" FROM \$Measurement WHERE \$timeFilter and value > 0",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "time_series",
          "select": [
            [
              {
                "params": [
                  "value"
                ],
                "type": "field"
              },
              {
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "\$Measurement (over time)",
      "tooltip": {
        "show": true,
        "showHistogram": true
      },
      "type": "heatmap",
      "xAxis": {
        "show": true
      },
      "yAxis": {
        "format": "ms",
        "logBase": 2,
        "show": true
      }
    },
    {
      "collapsed": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "gridPos": {
        "h": 1,
        "w": 24,
        "x": 0,
        "y": 30
      },
      "id": 20,
      "panels": [],
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "refId": "A"
        }
      ],
      "title": "Dashboard Row",
      "type": "row"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 37,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": [
      {
        "current": {
          "selected": true,
          "text": [
            "All"
          ],
          "value": [
            "$__all"
          ]
        },
        "hide": 0,
        "includeAll": true,
        "multi": true,
        "name": "Measurement",
        "options": [
          {
            "selected": false,
            "text": "All",
            "value": "\$__all"
          },
          {
            "selected": true,
            "text": "http_req_duration",
            "value": "http_req_duration"
          },
          {
            "selected": true,
            "text": "http_req_blocked",
            "value": "http_req_blocked"
          },
          {
            "selected": false,
            "text": "http_req_connecting",
            "value": "http_req_connecting"
          },
          {
            "selected": false,
            "text": "http_req_looking_up",
            "value": "http_req_looking_up"
          },
          {
            "selected": false,
            "text": "http_req_receiving",
            "value": "http_req_receiving"
          },
          {
            "selected": false,
            "text": "http_req_sending",
            "value": "http_req_sending"
          },
          {
            "selected": false,
            "text": "http_req_waiting",
            "value": "http_req_waiting"
          }
        ],
        "query": "http_req_duration,http_req_blocked,http_req_connecting,http_req_looking_up,http_req_receiving,http_req_sending,http_req_waiting",
        "skipUrlSync": false,
        "type": "custom"
      }
    ]
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "timezone": "browser",
  "title": "k6 Load Testing Results",
  "uid": "a1eVaFGVk",
  "version": 1,
  "weekStart": ""
}
EOF

systemctl daemon-reload
systemctl enable grafana-server.service
systemctl start grafana-server

## Install k6
mkdir -p /root/.gnupg/
chmod 600 /root/.gnupg/
gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
apt-get update
apt-get install k6 -y

## Create a dummy script for creating an (almost) empty InfluxDB database
mkdir -p /usr/share/k6/
cat > /usr/share/k6/script.js <<EOF
import http from 'k6/http';

export default function () {
}
EOF

## Run the dummy script
k6 run --out influxdb=http://localhost:8086/myk6db /usr/share/k6/script.js

wall "StackScripts is finished. Please check /var/log/stackscript.log"