#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f node-rev-proxy/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml down -v
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml down -v
docker-compose -p $COMPOSE_PROJECT -f fhir-server/blaze-server/docker-compose.yml down -v
docker-compose -p $COMPOSE_PROJECT -f fhir-server/hapi-fhir-server/docker-compose.yml down -v
