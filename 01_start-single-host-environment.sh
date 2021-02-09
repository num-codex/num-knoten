#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

echo "Create num node docker network, if it does not exist..."
if [ ! "$(docker network ls | grep num-node)" ]; then
docker network create num-node
fi

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml up -d

docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml up -d

docker-compose -p $COMPOSE_PROJECT -f fhir-server/blaze-server/docker-compose.yml up -d


echo "Waiting for gPAS to come up..."
docker wait ${COMPOSE_PROJECT}_gpasinit-patient_1 && docker wait ${COMPOSE_PROJECT}_gpasinit-fall_1
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml up -d
