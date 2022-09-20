#!/bin/bash

export PGPASSWORD=$KONG_PG_PASSWORD
export RUN_INTERVAL=${RUN_INTERVAL_SECONDS:-5}

## Uncomment these two lines for running from your desktop (for example after "kdev-admin") - remember to set Kong DB parameters at the top of the Makefile
# mkdir -p ~/.kube
# cp /mnt/kubectl/config ~/.kube/config

while true
do
  # Set up if new deployment
  if ! kubectl get secret audit-logger-tracking -n $STORAGE_NAMESPACE > /dev/null
  then
    echo "--> Storage secret does not exist, creating one"
    if ! kubectl create secret generic audit-logger-tracking --from-literal=OBJECTS_OFFSET="1970-01-01 00:00:00.000+00" --from-literal=REQUESTS_OFFSET="1970-01-01 00:00:00.000+00" -n $STORAGE_NAMESPACE > /dev/null
    then
      echo "--> FAIL: Could not create storage secret in $STORAGE_NAMESPACE namespace "
      exit 1
    fi
  fi

  # Get last offsets read
  export BEGIN_OBJECTS=$(kubectl get secret audit-logger-tracking -n $STORAGE_NAMESPACE -o yaml | yq e .data.OBJECTS_OFFSET - | base64 -d -)
  export BEGIN_REQUESTS=$(kubectl get secret audit-logger-tracking -n $STORAGE_NAMESPACE -o yaml | yq e .data.REQUESTS_OFFSET - | base64 -d -)

  # Calculate new end offsets
  export END_OBJECTS=$(date -u +"%Y-%m-%d %H:%M:%S.%3N+00" -d "$(date) + 2591999 seconds")
  export END_REQUESTS=$(date -u +"%Y-%m-%d %H:%M:%S.%3N+00")

  echo "--> START: $BEGIN_REQUESTS AUDIT LOGS"

  cat print_audit_objects.sql | envsubst > /tmp/statement.sql
  if psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE -a -t -P pager=off -f /tmp/statement.sql
  then
    cat print_audit_requests.sql | envsubst > /tmp/statement.sql
    if psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE -a -t -P pager=off -f /tmp/statement.sql
    then
      kubectl create secret generic audit-logger-tracking --from-literal=OBJECTS_OFFSET="$END_OBJECTS" --from-literal=REQUESTS_OFFSET="$END_REQUESTS" -n $STORAGE_NAMESPACE --dry-run=client -o yaml > /tmp/secret.yaml
      kubectl apply -n $STORAGE_NAMESPACE -f /tmp/secret.yaml > /dev/null

      echo "-->  END: $BEGIN_REQUESTS AUDIT LOGS"
    else
      echo "--> FAIL: Could not execute audit_requests query on Kong database"
      exit 1
    fi
  else
    echo "--> FAIL: Could not execute audit_objects query on Kong database"
    exit 1
  fi

  sleep $RUN_INTERVAL
done
