# Kong Audit Log Exporter

Logs all entries from the audit tables to stdout stream, for ingest by Filebeat, or pushing to a HTTP endpoint like Splunk HEC.

## Installation

The install requires three separate parts.

### 1. Create a Read-Only Postgres User

This program operates by reading the appropriate PostgreSQL tables for the Kong Enterprise installation. It only needs to be able to read TWO tables, which helps to protect your actual API deployment data and credentials.

This section differs wildly for each setup, but essentially you just need:

* A new postgres role, with read on tables: `audit_objects` and `audit_requests`
* A new postgres user, with password authentication, mapped to this role

### 2. Build the Image

This program is designed to run in Kubernetes and so you need to build the container image, containing the program code and all requirements, and push it to a private image registry that is accessible by the Kong "control plane" Kubernetes clusteer.

Building the image is easy:

```sh
## Log into the private registry here first
$ docker build -t registry.my.local/audit-log-exporter:latest .
$ docker push registry.my.local/audit-log-exporter:latest
```

### 3. Install the Helm Chart

This repository is also a barebones Helm chart. It can be installed by specifying the relative path of this cloned repository.

First, you need to create a `values-override.yaml` file and change some settings specific to your environment:

```yaml
configuration:
  storageNamespace: kong  # this defines which namespace will store the 'tracking' record, which tells the program its last run time; just set it to the same namespace this program is going into
  runIntervalSeconds: 300  # run interval; on each 'run', the Kubernetes secret is updated, so keep this realistic (e.g. 5 minutes here)
  mode: http  # choices are http or stdout; 'stdout' prints straight to the console, so you can just scrape the data with e.g. fluent-bit
  http:
    ## If 'http' mode is set, specify the endpoint and auth header required to POST each JSON-formatted record
    endpoint: http://audit-log-receiver:8080/v1/logs
    header:
      name: "Authorization"
      value: "Splunk PLACEHOLDER"
    eventKey: "kong-audit-logs"  # this is specific to Splunk, and adds the JSON key "event" to each POST datum
  postgres:
    ## In this block, enter credentials to be able to read postgres tables 'audit_objects' and 'audit_requests'
    database: kong
    host: control-plane-postgresql.kong.svc.cluster.local
    username: kong
    password: kong

image:
  ## Finally, adjust the image section to point to your private registry; use pullSecret if registry authentication is required
  repository: registry.my.local/audit-log-exporter
  tag: latest 
  pullPolicy: Always
```

**Now install it:**

```sh
$ helm upgrade -i audit-log-exporter . -f values-override.yaml -n <namespace>
```
