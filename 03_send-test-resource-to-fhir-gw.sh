#!/bin/sh
curl \
    -L \
    -v \
    -H 'Content-Type:application/json' \
    -d "$(cat fhir-gw/test-fhir-resource.json)" \
    https://localhost/fhir-gw/fhir
