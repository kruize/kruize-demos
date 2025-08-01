#!/bin/bash

cd kruize-operator
make undeploy
cd ../
rm -rf kruize-operator
oc delete deployment kruize-ui-nginx -n openshift-tuning
oc delete deployment kruize -n openshift-tuning
oc delete deployment kruize-db -n openshift-tuning


