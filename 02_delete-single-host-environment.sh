#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f node-rev-proxy/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f fhir-server/blaze-server/docker-compose.yml down
docker-compose -p $COMPOSE_PROJECT -f fhir-server/hapi-fhir-server/docker-compose.yml down
docker volume rm ${COMPOSE_PROJECT}_fhir-gateway-data
docker volume rm ${COMPOSE_PROJECT}_gpas-data
docker volume rm ${COMPOSE_PROJECT}_pg-data-volume
docker volume rm ${COMPOSE_PROJECT}_blaze-data
docker volume rm ${COMPOSE_PROJECT}_hapi-data

echo "Remove num node docker network, if it exists..."
if [ "$(docker network ls | grep num-node)" ]; then
docker network remove num-node
fi

