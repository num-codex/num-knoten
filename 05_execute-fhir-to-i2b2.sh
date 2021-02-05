#!/bin/bash

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=demouser i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources'"

# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=demouser i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources'"
