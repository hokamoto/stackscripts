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

## Install iftop
apt install iftop -y

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
grafana-cli plugins install blackmirror1-singlestat-math-panel

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
cat > /var/lib/grafana/dashboards/k6.json <<'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "datasource",
          "uid": "grafana"
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
  "description": "A dashboard for visualizing results from the k6.io load testing tool, using the InfluxDB exporter.\r\n\r\ninspire from https://grafana.com/dashboards/2587 & k6 cloud dashboard.\r\n\r\nsimple & informative dashboard\r\n\r\n",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "gnetId": 14801,
  "graphTooltip": 2,
  "id": 2,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 0,
        "y": 0
      },
      "id": 78,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "max"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "value"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\")/${interval_value} FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "title": "Peak RPS ",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "mappings": [],
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
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_req_duration.max"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              },
              {
                "id": "thresholds",
                "value": {
                  "mode": "absolute",
                  "steps": [
                    {
                      "color": "green",
                      "value": null
                    },
                    {
                      "color": "super-light-orange",
                      "value": 500
                    },
                    {
                      "color": "light-orange",
                      "value": 3000
                    },
                    {
                      "color": "red",
                      "value": 30000
                    }
                  ]
                }
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 4,
        "y": 0
      },
      "id": 77,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "max"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "value"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT max(\"value\") FROM \"http_req_duration\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "title": "Max Response Time",
      "type": "stat"
    },
    {
      "circleBackground": false,
      "colorBackground": false,
      "colorValue": true,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "defaultColor": "rgb(117, 117, 117)",
      "format": "percent",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 8,
        "y": 0
      },
      "id": 87,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "math": "(error/total)*100",
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "pluginVersion": "7.5.6",
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sortOrder": "asc",
      "sortOrderOptions": [
        {
          "text": "Ascending",
          "value": "asc"
        },
        {
          "text": "Descending",
          "value": "desc"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "alias": "error",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE (\"status\" != '200' AND \"status\" != '201') AND $timeFilter group by time(${interval_value}s)",
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
        },
        {
          "alias": "total",
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "hide": false,
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
          "rawQuery": true,
          "refId": "B",
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
      "thresholds": [
        {
          "$$hashKey": "object:162",
          "color": "#73BF69",
          "value": 1
        },
        {
          "$$hashKey": "object:219",
          "color": "#FF9830",
          "value": 5
        },
        {
          "$$hashKey": "object:222",
          "color": "#FADE2A",
          "value": 10
        },
        {
          "$$hashKey": "object:225",
          "color": "#F2495C",
          "value": 50
        }
      ],
      "title": "Error Rate",
      "tooltip": {
        "show": true
      },
      "type": "blackmirror1-singlestat-math-panel",
      "valueFontSize": "80%",
      "valueMappingColorBackground": "#767171",
      "valueMaps": [
        {
          "op": "=",
          "text": "No data",
          "value": "null"
        }
      ],
      "valueName": "total"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 10,
        "w": 11,
        "x": 13,
        "y": 0
      },
      "id": 74,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "sum"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "value"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "title": "Request Made",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "decimals": 0,
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 0,
        "y": 5
      },
      "id": 84,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "max"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "auto"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT max(\"value\") FROM \"vus_max\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "title": "VUS Max ",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "decimals": 2,
          "mappings": [],
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
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_req_duration.mean"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              },
              {
                "id": "thresholds",
                "value": {
                  "mode": "absolute",
                  "steps": [
                    {
                      "color": "green",
                      "value": null
                    },
                    {
                      "color": "super-light-orange",
                      "value": 500
                    },
                    {
                      "color": "light-orange",
                      "value": 3000
                    },
                    {
                      "color": "red",
                      "value": 30000
                    }
                  ]
                }
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 4,
        "y": 5
      },
      "id": 80,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "mean"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "value"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT mean(\"value\") FROM \"http_req_duration\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "title": "Average Response Time",
      "type": "stat"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              }
            ]
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 4,
        "x": 8,
        "y": 5
      },
      "id": 79,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "sum"
          ],
          "fields": "",
          "values": false
        },
        "text": {},
        "textMode": "value"
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE (\"status\" != '200' AND \"status\" != '201') AND $timeFilter group by time(${interval_value}s)",
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
      "title": "HTTP Failures",
      "type": "stat"
    },
    {
      "aliasColors": {
        "http_req_duration.Response_Time": "dark-purple"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 10
      },
      "hiddenSeries": false,
      "id": 75,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "rightSide": true,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "$$hashKey": "object:219",
          "alias": "http_reqs.sum",
          "yaxis": 1
        },
        {
          "$$hashKey": "object:220",
          "alias": "http_req_duration.Response_Time",
          "yaxis": 2
        },
        {
          "$$hashKey": "object:221",
          "alias": "http_reqs.RPS",
          "yaxis": 1
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT sum(\"value\")/${interval_value} as RPS FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
          "rawQuery": true,
          "refId": "B",
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
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT sum(\"value\") as iteration FROM \"iterations\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
                "type": "mean"
              }
            ]
          ],
          "tags": []
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT mean(\"value\") as VUS FROM \"vus\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
                "params": [],
                "type": "mean"
              }
            ]
          ],
          "tags": []
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT mean(\"value\") as Response_Time FROM \"http_req_duration\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
                "type": "mean"
              }
            ]
          ],
          "tags": []
        }
      ],
      "thresholds": [],
      "timeRegions": [],
      "title": "ALL METRICS ",
      "tooltip": {
        "shared": true,
        "sort": 0,
        "value_type": "individual"
      },
      "transformations": [],
      "type": "graph",
      "xaxis": {
        "mode": "time",
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "none",
          "label": "Request Per Second (rps)",
          "logBase": 1,
          "show": true
        },
        {
          "format": "ms",
          "label": "Time",
          "logBase": 2,
          "min": "1",
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": -2
      }
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "description": "",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "fillOpacity": 80,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineWidth": 1
          },
          "displayName": "Request per second (in ms)",
          "mappings": [],
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
          }
        },
        "overrides": [
          {
            "__systemRef": "hideSeriesFrom",
            "matcher": {
              "id": "byNames",
              "options": {
                "mode": "exclude",
                "names": [
                  "Request per second (in ms)"
                ],
                "prefix": "All except:",
                "readOnly": true
              }
            },
            "properties": [
              {
                "id": "custom.hideFrom",
                "value": {
                  "legend": false,
                  "tooltip": false,
                  "viz": true
                }
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 20
      },
      "id": 89,
      "options": {
        "bucketOffset": 0,
        "combine": true,
        "legend": {
          "calcs": [],
          "displayMode": "table",
          "placement": "bottom",
          "showLegend": true
        }
      },
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT (\"value\") as Response_Time FROM \"http_req_duration\" WHERE $timeFilter  fill(null)",
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
                "type": "first"
              }
            ]
          ],
          "tags": []
        }
      ],
      "title": "Histogram - Response Time",
      "type": "histogram"
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
      "fieldConfig": {
        "defaults": {},
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 28
      },
      "hiddenSeries": false,
      "id": 85,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(3s) fill(null)",
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
      "thresholds": [],
      "timeRegions": [],
      "title": "Request ",
      "tooltip": {
        "shared": false,
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
          "label": "Total Request ",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": false
        }
      ],
      "yaxis": {
        "align": false
      }
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
      "fieldConfig": {
        "defaults": {
          "unit": "ms"
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 38
      },
      "hiddenSeries": false,
      "id": 86,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT mean(\"value\") as Response_Time FROM \"http_req_duration\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "thresholds": [],
      "timeRegions": [],
      "title": "Response Time ",
      "tooltip": {
        "shared": false,
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
          "label": "Response Time",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": false
        }
      ],
      "yaxis": {
        "align": false
      }
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
      "fieldConfig": {
        "defaults": {},
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 48
      },
      "hiddenSeries": false,
      "id": 73,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\")/${interval_value} FROM \"http_reqs\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "thresholds": [],
      "timeRegions": [],
      "title": "Request Per Second",
      "tooltip": {
        "shared": false,
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
          "label": "Request Per Second (rps)",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": false
        }
      ],
      "yaxis": {
        "align": false
      }
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
      "fieldConfig": {
        "defaults": {},
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 58
      },
      "hiddenSeries": false,
      "id": 82,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT sum(\"value\") FROM \"iterations\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "thresholds": [],
      "timeRegions": [],
      "title": "Iteration ",
      "tooltip": {
        "shared": false,
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
          "label": "Request Per Second (rps)",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": false
        }
      ],
      "yaxis": {
        "align": false
      }
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
      "fieldConfig": {
        "defaults": {},
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "http_reqs.sum"
            },
            "properties": [
              {
                "id": "unit",
                "value": "none"
              }
            ]
          }
        ]
      },
      "fill": 1,
      "fillGradient": 2,
      "gridPos": {
        "h": 11,
        "w": 24,
        "x": 0,
        "y": 68
      },
      "hiddenSeries": false,
      "id": 81,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": false,
        "hideEmpty": false,
        "max": true,
        "min": false,
        "show": true,
        "total": true,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "nullPointMode": "null",
      "options": {
        "alertThreshold": true
      },
      "percentage": false,
      "pluginVersion": "9.3.0",
      "pointradius": 4,
      "points": true,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT mean(\"value\") FROM \"vus\" WHERE $timeFilter GROUP BY time(${interval_value}s) fill(null)",
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
      "thresholds": [],
      "timeRegions": [],
      "title": "Average VUS ",
      "tooltip": {
        "shared": false,
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
          "label": "Request Per Second (rps)",
          "logBase": 1,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "show": false
        }
      ],
      "yaxis": {
        "align": false
      }
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "custom": {
            "displayMode": "auto",
            "filterable": false,
            "inspect": false
          },
          "mappings": [],
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
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "P95 (Response TIme)"
            },
            "properties": [
              {
                "id": "custom.displayMode",
                "value": "color-background"
              },
              {
                "id": "unit",
                "value": "ms"
              },
              {
                "id": "thresholds",
                "value": {
                  "mode": "absolute",
                  "steps": [
                    {
                      "color": "green",
                      "value": null
                    },
                    {
                      "color": "super-light-orange",
                      "value": 200
                    },
                    {
                      "color": "light-orange",
                      "value": 3000
                    },
                    {
                      "color": "red",
                      "value": 30000
                    }
                  ]
                }
              }
            ]
          },
          {
            "matcher": {
              "id": "byName",
              "options": "MIN (Response TIme)"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              }
            ]
          },
          {
            "matcher": {
              "id": "byName",
              "options": "AVG (Response TIme)"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              }
            ]
          },
          {
            "matcher": {
              "id": "byName",
              "options": "MAX (Response TIme)"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              }
            ]
          },
          {
            "matcher": {
              "id": "byName",
              "options": "P99 (Response TIme)"
            },
            "properties": [
              {
                "id": "unit",
                "value": "ms"
              }
            ]
          },
          {
            "matcher": {
              "id": "byName",
              "options": "URL"
            },
            "properties": [
              {
                "id": "custom.width",
                "value": 549
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 11,
        "w": 24,
        "x": 0,
        "y": 79
      },
      "id": 83,
      "options": {
        "footer": {
          "fields": "",
          "reducer": [
            "sum"
          ],
          "show": false
        },
        "showHeader": true,
        "sortBy": [
          {
            "desc": true,
            "displayName": "P95 (Response TIme)"
          }
        ]
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "hide": true,
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT status from (SELECT \"method\", \"value\" FROM \"http_req_duration\" WHERE $timeFilter GROUP BY \"name\",\"status\" )",
          "rawQuery": true,
          "refId": "B",
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
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "hide": true,
          "measurement": "data_sent",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT count(*),\"status\" from (SELECT \"method\", \"value\", \"status\" FROM \"http_req_duration\" WHERE $timeFilter GROUP BY \"name\",\"status\" )",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "table",
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
        },
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "hide": false,
          "measurement": "http_req_duration",
          "orderByTime": "ASC",
          "policy": "default",
          "query": "SELECT percentile(\"value\", 95) as PERCENTILE_95, percentile(\"value\", 99) as PERCENTILE_99, max(\"value\") as  max_response_time, mean(\"value\") as  avg_response_time, min(\"value\") as  min_response_time, count(\"value\") as  count    FROM \"http_req_duration\" WHERE $timeFilter  GROUP BY \"name\",\"status\",\"method\"  fill(null)",
          "rawQuery": true,
          "refId": "C",
          "resultFormat": "table",
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
        }
      ],
      "title": "HTTP REQUEST",
      "transformations": [
        {
          "id": "organize",
          "options": {
            "excludeByName": {
              "Time": true
            },
            "indexByName": {
              "PERCENTILE_95": 8,
              "PERCENTILE_99": 9,
              "Time": 0,
              "avg_response_time": 6,
              "count": 4,
              "max_response_time": 7,
              "method": 2,
              "min_response_time": 5,
              "name": 1,
              "status": 3
            },
            "renameByName": {
              "PERCENTILE_95": "P95 (Response TIme)",
              "PERCENTILE_99": "P99 (Response TIme)",
              "Time": "",
              "avg_response_time": "AVG (Response TIme)",
              "count": "COUNT",
              "max_response_time": "MAX (Response TIme)",
              "method": "METHOD",
              "min_response_time": "MIN (Response TIme)",
              "name": "URL",
              "status": "STATUS"
            }
          }
        }
      ],
      "type": "table"
    },
    {
      "datasource": {
        "type": "influxdb",
        "uid": "P951FEA4DE68E13C5"
      },
      "fieldConfig": {
        "defaults": {
          "custom": {
            "displayMode": "auto",
            "filterable": false,
            "inspect": false
          },
          "mappings": [],
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
          }
        },
        "overrides": [
          {
            "matcher": {
              "id": "byName",
              "options": "Time"
            },
            "properties": [
              {
                "id": "custom.width"
              }
            ]
          }
        ]
      },
      "gridPos": {
        "h": 5,
        "w": 24,
        "x": 0,
        "y": 90
      },
      "id": 72,
      "options": {
        "footer": {
          "fields": "",
          "reducer": [
            "sum"
          ],
          "show": false
        },
        "showHeader": true,
        "sortBy": []
      },
      "pluginVersion": "9.3.0",
      "targets": [
        {
          "datasource": {
            "type": "influxdb",
            "uid": "P951FEA4DE68E13C5"
          },
          "groupBy": [
            {
              "params": [
                "$__interval"
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
          "query": "SELECT sum(\"value\") FROM \"http_reqs\" WHERE (\"status\" != '200' AND \"status\" != '201' ) AND $timeFilter group by status, method, \"name\"",
          "rawQuery": true,
          "refId": "A",
          "resultFormat": "table",
          "select": [
            [
              {
                "params": [
                  "url"
                ],
                "type": "field"
              }
            ]
          ],
          "tags": [
            {
              "key": "status",
              "operator": "!=",
              "value": "200"
            }
          ]
        }
      ],
      "title": "Error Detail",
      "type": "table"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 37,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": [
      {
        "allValue": "*",
        "current": {
          "selected": false,
          "text": "All",
          "value": "$__all"
        },
        "datasource": {
          "type": "influxdb",
          "uid": "P951FEA4DE68E13C5"
        },
        "definition": "SHOW TAG VALUES FROM \"http_req_duration\" WITH KEY = \"name\"",
        "hide": 0,
        "includeAll": true,
        "label": "URL",
        "multi": false,
        "name": "URL",
        "options": [],
        "query": "SHOW TAG VALUES FROM \"http_req_duration\" WITH KEY = \"name\"",
        "refresh": 2,
        "regex": "",
        "skipUrlSync": false,
        "sort": 1,
        "tagValuesQuery": "",
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "current": {
          "selected": true,
          "text": "3",
          "value": "3"
        },
        "hide": 0,
        "includeAll": false,
        "label": "interval_value",
        "multi": false,
        "name": "interval_value",
        "options": [
          {
            "selected": true,
            "text": "3",
            "value": "3"
          },
          {
            "selected": false,
            "text": "5",
            "value": "5"
          },
          {
            "selected": false,
            "text": "10",
            "value": "10"
          }
        ],
        "query": "3,5,10",
        "queryValue": "",
        "skipUrlSync": false,
        "type": "custom"
      },
      {
        "current": {
          "selected": false,
          "text": "InfluxDB",
          "value": "InfluxDB"
        },
        "hide": 0,
        "includeAll": false,
        "label": "Data Source",
        "multi": false,
        "name": "data_source",
        "options": [],
        "query": "influxdb",
        "queryValue": "",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "type": "datasource"
      }
    ]
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "1s",
      "10s",
      "30s",
      "5m",
      "30m"
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
  "title": "K6 Dashboard",
  "uid": "ReuNR5Aik",
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