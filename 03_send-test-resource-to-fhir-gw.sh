#!/bin/sh
curl \
    -L \
    -v \
    -H 'Content-Type:application/json' \
    -d "$(cat fhir-gw/test-fhir-resource.json)" \
    http://localhost:18080/fhir
