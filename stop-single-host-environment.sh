#!/bin/bash

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml down
