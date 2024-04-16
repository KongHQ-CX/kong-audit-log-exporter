# Kong Audit Log Exporter

Logs all entries from the audit tables to stdout stream, for ingest by Filebeat, or pushing to a HTTP endpoint like Splunk HEC.

## Installation - Konnect

For Konnect-based installations, you should use an [audit log webhook](https://docs.konghq.com/konnect/org-management/audit-logging/webhook/)

This requires a HTTPS endpoint, hosted by you (or in your cloud), that will receive the JSON-format payload events.

In this repository, we provide two examples:

### Example 1 - Kong Serverless Function

This is a "service-less" route that simply received the payload, and prints it to the Kong data-plane log. This allows you to host the audit payload receiver directly on one of your Kong runtime group data plane deployments, with no extra hardware.

Your existing log scraper can pick this up, where you can then search through it later.

It sets up a route in your Kong data plane at "https://{kong_hostname}/audit-logs" which can be configured as the payload target for audit webhooks, inside the Konnect UI.

**For this to work, you need to add TWO packages into the Lua trusted sandbox:**

```yaml
untrusted_lua_sandbox_requires: "kong.tools.utils,kong.tools.gzip"
```

**or in environment variables:**

```sh
KONG_UNTRUSTED_LUA_SANDBOX_REQUIRES="kong.tools.utils,kong.tools.gzip"
```

When it's running correctly, you should receive audit log statements in the Kong logs for this data-plane, which look like:

```
{"started_at":1702295653851,"client_ip":"10.42.0.1","audit_payload":"{\n  \"user\": \"jackt\",\n  \"action\": \"CREATE\",\n  \"object\": \"{\\\"type\\\":\\\"route\\\",\\\"name\\\":\\\"echo-server\\\"\"\n}\n\n"}
```

[The deck file is located here](./konnect/kong-logger-function.yaml)

### Example 2 - Lambda Function

This is a Python program that can be hosted as e.g. an AWS Lambda function, or Azure Container App.

It requires some load balancer or network exposure in order to actually receive the events from the Konnect Cloud.

[The Python script is located here](./konnect/python-lambda-print-audits.py)

[There is also an all-in-one Kube deployment, to help get started](./konnect/python-lambda-print-audits-kube-deployment.yaml)

## Installation - On-Prem

This install requires three separate parts.

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

#### HTTP Endpoint Example:

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

#### Console Output Example:

```yaml
configuration:
  storageNamespace: kong  # this defines which namespace will store the 'tracking' record, which tells the program its last run time; just set it to the same namespace this program is going into
  runIntervalSeconds: 300  # run interval; on each 'run', the Kubernetes secret is updated, so keep this realistic (e.g. 5 minutes here)
  mode: stdout
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
