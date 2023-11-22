#!/bin/bash

echo "-> STARTING UP"

export PGPASSWORD=$KONG_PG_PASSWORD
export RUN_INTERVAL=${RUN_INTERVAL_SECONDS:-5}
export TRACKING_SECRET_NAME="audit-log-exporter-storage-tracking"

## Uncomment these two lines for running from your desktop (for example after "kdev-admin") - remember to set Kong DB parameters at the top of the Makefile
# mkdir -p ~/.kube
# cp /mnt/kubectl/config ~/.kube/config

while true
do
  # Set up if new deployment
  if ! kubectl get secret $TRACKING_SECRET_NAME -n $STORAGE_NAMESPACE > /dev/null
  then
    echo "--> Storage secret does not exist, trying to create one"
    if ! kubectl create secret generic $TRACKING_SECRET_NAME --from-literal=OBJECTS_OFFSET="1970-01-01 00:00:00.000+00" --from-literal=REQUESTS_OFFSET="1970-01-01 00:00:00.000+00" -n $STORAGE_NAMESPACE > /dev/null
    then
      echo "--> FAIL: Could not create storage secret '$TRACKING_SECRET_NAME' in the '$STORAGE_NAMESPACE' namespace "
      exit 1
    fi
  fi

  # Get last offsets read
  export BEGIN_OBJECTS=$(kubectl get secret $TRACKING_SECRET_NAME -n $STORAGE_NAMESPACE -o yaml | yq e .data.OBJECTS_OFFSET - | base64 -d -)
  export BEGIN_REQUESTS=$(kubectl get secret $TRACKING_SECRET_NAME -n $STORAGE_NAMESPACE -o yaml | yq e .data.REQUESTS_OFFSET - | base64 -d -)

  # Calculate new end offsets
  export END_OBJECTS=$(date -u +"%Y-%m-%d %H:%M:%S.%3N+00" -d "$(date) + 2591999 seconds")
  export END_REQUESTS=$(date -u +"%Y-%m-%d %H:%M:%S.%3N+00")

  echo "-> START: $BEGIN_REQUESTS AUDIT LOGS"

  if [ "$RUN_MODE" == "http" ]
  then
    echo "--> Running for Object Logs"
    cat print_audit_objects.sql | envsubst > /tmp/objects_statement.sql

    psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE --single-transaction --set AUTOCOMMIT=off --set ON_ERROR_STOP=on --no-align -t --field-separator ' ' --quiet -P pager=off -f /tmp/objects_statement.sql | while read -r RECORD
    do
      echo "--> New object records to POST"
      NEW_RECORD=$(echo $RECORD | yq -P eval -o=json -I=0 '.event = strenv(HTTP_EVENT_KEY)' -)
      if ! curl -s -H 'Content-Type: application/json' -H "$HTTP_HEADER_NAME: $HTTP_HEADER_VALUE" -d "$NEW_RECORD" $HTTP_ENDPOINT
      then
        echo "--> FAIL: Could not send last request, quitting for safety"
        exit 1
      fi
      echo ""
    done

    echo "--> Running for Request Logs"
    cat print_audit_requests.sql | envsubst > /tmp/requests_statement.sql
    
    psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE --single-transaction --set AUTOCOMMIT=off --set ON_ERROR_STOP=on --no-align -t --field-separator ' ' --quiet -P pager=off -f /tmp/requests_statement.sql | while read -r RECORD
    do
      echo "--> New request records to POST"
      NEW_RECORD=$(echo $RECORD | yq -P eval -o=json -I=0 '.event = strenv(HTTP_EVENT_KEY)' -)
      if ! curl -s -H 'Content-Type: application/json' -H "$HTTP_HEADER_NAME: $HTTP_HEADER_VALUE" -d "$NEW_RECORD" $HTTP_ENDPOINT
      then
        echo "--> FAIL: Could not send last request, quitting for safety"
        exit 1
      fi
      echo ""
    done

    echo "--> UPDATING KUBE SECRET VALUES..."
    kubectl create secret generic $TRACKING_SECRET_NAME --from-literal=OBJECTS_OFFSET="$END_OBJECTS" --from-literal=REQUESTS_OFFSET="$END_REQUESTS" -n $STORAGE_NAMESPACE --dry-run=client -o yaml > /tmp/secret.yaml
    kubectl apply -n $STORAGE_NAMESPACE -f /tmp/secret.yaml > /dev/null
    
    echo "->  END: $BEGIN_REQUESTS AUDIT LOGS"
  else
    cat print_audit_objects.sql | envsubst > /tmp/statement.sql
    if psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE -a -t -P pager=off -f /tmp/statement.sql
    then
      cat print_audit_requests.sql | envsubst > /tmp/statement.sql
      if psql -U $KONG_PG_USER -h $KONG_PG_HOST -d $KONG_PG_DATABASE -a -t -P pager=off -f /tmp/statement.sql
      then
        kubectl create secret generic $TRACKING_SECRET_NAME --from-literal=OBJECTS_OFFSET="$END_OBJECTS" --from-literal=REQUESTS_OFFSET="$END_REQUESTS" -n $STORAGE_NAMESPACE --dry-run=client -o yaml > /tmp/secret.yaml
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
  fi

  sleep $RUN_INTERVAL
done

echo "-> LOOP HAS TERMINATED"
