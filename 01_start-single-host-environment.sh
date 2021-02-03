#!/bin/bash

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml up -d

docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml up -d

docker wait ${COMPOSE_PROJECT}_gpasinit-patient_1 && docker wait ${COMPOSE_PROJECT}_gpasinit-fall_1
docker-compose -p $COMPOSE_PROJECT -f monitoring/docker-compose.yml up -d

# Initialize i2b2 ETL:

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "psql -U postgres -d i2b2 -a -f /create-fdw.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Creating i2b2 FHIR Trigger ...'; psql -U postgres -d i2b2 -a -f /i2b2-FHIR-Trigger.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Loading i2b2 Ontology ...'; psql -U postgres -d i2b2 -a -f /i2b2Ontology.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -f /Postprocessing.sql > /dev/null"

