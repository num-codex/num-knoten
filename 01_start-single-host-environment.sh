#!/bin/bash

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml up -d

docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml up -d

docker wait ${COMPOSE_PROJECT}_gpasinit-patient_1 && docker wait ${COMPOSE_PROJECT}_gpasinit-fall_1
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml up -d

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg psql -U postgres -d i2b2 -a -f /create-fdw.sql
