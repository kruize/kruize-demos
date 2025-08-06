#!/bin/bash

cd kruize-operator
make undeploy
cd ../
rm -rf kruize-operator
oc delete deployment kruize-ui-nginx -n openshift-tuning
oc delete deployment kruize -n openshift-tuning
oc delete deployment kruize-db -n openshift-tuning


# Delete existing resources to force recreation
oc delete clusterrole kruize-recommendation-updater kruize-monitoring-access 2>/dev/null || true
oc delete clusterrolebinding kruize-monitoring-view kruize-recommendation-updater-crb kruize-prometheus-reader kruize-system-reader kruize-monitoring-access-crb 2>/dev/null || true

# Delete ConfigMap to trigger recreation
oc delete configmap kruizeconfig -n openshift-tuning
oc delete deployment kruize -n openshift-tuning