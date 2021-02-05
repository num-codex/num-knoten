#!/bin/bash

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f odm2fhir/docker-compose.yml up
docker wait ${COMPOSE_PROJECT}_odm2fhir_1
docker rm ${COMPOSE_PROJECT}_odm2fhir_1
