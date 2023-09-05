---
title: Show failing scraping Prometheus jobs in Grafana
tags: grafana
---


I wanted to see a list of all Prometheus scraping jobs and next to that, those that were failing.

In the UI, we can clearly see which scraper is up or down:

![Example Failing Prometheus Scraper](/images/2023-08-14-show-failing-scraping-prometheus-jobs-in-grafana/Prometheus Failing Scraper Job.png)

I wanted to see this in Grafana too, like this:

![Failing Scraper Job from Grafana](/images/2023-08-14-show-failing-scraping-prometheus-jobs-in-grafana/Failing Scraper Job from Grafana.png)

This was more complicated than expected, so it's worth a blog post to explain how I did it.

# Data Source

To see which scraper is failing in Grafana, we must first make Prometheus scrape its own internal
metrics. Those are by default exposed under the `/metrics` path of the Prometheus' endpoint. In Prometheus' config, add the
following scraping job:

```yaml
- job_name: prometheus_internal
  static_configs:
  - targets:
    - 127.0.0.1:9090
```

This exposes a lot of metrics but those of interest for us are:

- `prometheus_sd_discovered_targets` which shows all scraping jobs.
- `net_conntrack_dialer_conn_failed_total` which shows a time series of failures to scrape.

# Query

What interests us from `prometheus_sd_discovered_targets` is to see that it has a `config` label which we can join on.

![Labels for `prometheus_sd_discovered_targets` metric.](/images/2023-08-14-show-failing-scraping-prometheus-jobs-in-grafana/prometheus_sd_discovered_targets labels.png)

From the `net_conntrack_dialer_conn_failed_total` metric, the label we will use to join on is `dialer_name`. It has also a `reason` label that could be useful for further investigation, but we don't care for this visualization.

![Labels for `net_conntrack_dialer_conn_failed_total` metric.](/images/2023-08-14-show-failing-scraping-prometheus-jobs-in-grafana/failure_raw_metric.png)

# Panel JSON

If you want to copy it, here is the panel JSON. You will need to update a few things including the datasource.

```json
{
  "datasource": {
    "uid": "df80f9f5-97d7-4112-91d8-72f523a02b09",
    "type": "prometheus"
  },
  "fieldConfig": {
    "defaults": {
      "custom": {
        "lineWidth": 0,
        "fillOpacity": 70,
        "spanNulls": false
      },
      "color": {
        "mode": "fixed",
        "fixedColor": "red"
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
    "overrides": []
  },
  "gridPos": {
    "h": 8,
    "w": 12,
    "x": 0,
    "y": 0
  },
  "id": 3,
  "options": {
    "mergeValues": true,
    "showValue": "never",
    "alignValue": "center",
    "rowHeight": 0.9,
    "legend": {
      "showLegend": true,
      "displayMode": "list",
      "placement": "bottom"
    },
    "tooltip": {
      "mode": "single",
      "sort": "none"
    }
  },
  "pluginVersion": "10.0.2",
  "targets": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "df80f9f5-97d7-4112-91d8-72f523a02b09"
      },
      "editorMode": "builder",
      "expr": "prometheus_sd_discovered_targets",
      "hide": false,
      "instant": false,
      "legendFormat": "{{config}}",
      "range": true,
      "refId": "All"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "df80f9f5-97d7-4112-91d8-72f523a02b09"
      },
      "editorMode": "code",
      "expr": "label_replace(increase((sum by(dialer_name) (net_conntrack_dialer_conn_failed_total))[15m:1m]), \"config\", \"$1\", \"dialer_name\", \"(.*)\") > 10",
      "hide": false,
      "instant": false,
      "legendFormat": "{{dialer_name}}",
      "range": true,
      "refId": "Failed"
    }
  ],
  "title": "Scraping jobs",
  "transformations": [
    {
      "id": "labelsToFields",
      "options": {
        "keepLabels": [
          "config"
        ],
        "mode": "columns"
      }
    },
    {
      "id": "merge",
      "options": {}
    },
    {
      "id": "organize",
      "options": {
        "excludeByName": {
          "prometheus_sd_discovered_targets": true
        },
        "indexByName": {},
        "renameByName": {
          "prometheus_sd_discovered_targets": ""
        }
      }
    },
    {
      "id": "partitionByValues",
      "options": {
        "fields": [
          "config"
        ]
      }
    }
  ],
  "type": "state-timeline"
}
```
