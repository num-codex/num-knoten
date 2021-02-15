#!/bin/sh
curl \
    -L \
    -v \
    -H 'Content-Type:application/json' \
    -d "@fhir-gw/test-fhir-resource.json" \
    http://localhost:18080/fhir-gw/fhir
