#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten
export PORT_BLAZE_FHIR=""
export PORT_HAPI_FHIR=""
FHIR_SERVER=${FHIR_SERVER:-hapi}
NGINX_PROXY_ENABLED=${NGINX_PROXY_ENABLED:-true}

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml up -d
docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml up -d

if [ "$FHIR_SERVER" = "blaze" ]; then
    echo "Starting up FHIR-Server: Blaze"
    docker-compose -p $COMPOSE_PROJECT -f fhir-server/blaze-server/docker-compose.yml up -d
elif [ "$FHIR_SERVER" = "hapi" ]; then
    echo "Starting up FHIR-Server: HAPI"
    docker-compose -p $COMPOSE_PROJECT -f fhir-server/hapi-fhir-server/docker-compose.yml up -d
fi

if [ "$NGINX_PROXY_ENABLED" = true ]; then
    echo "Starting up nginx reverse proxy server"
    docker-compose -p $COMPOSE_PROJECT -f node-rev-proxy/docker-compose.yml up -d
fi

echo "Waiting for gPAS to come up..."
docker wait ${COMPOSE_PROJECT}_gpasinit-patient_1 && docker wait ${COMPOSE_PROJECT}_gpasinit-fall_1
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml up -d
