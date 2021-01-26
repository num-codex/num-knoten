#!/bin/bash
curl \
    -L \
    -v \
    -H 'Content-Type:application/json' \
    -d "$(cat test-fhir-resource.json)" \
    http://localhost:18080/fhir
