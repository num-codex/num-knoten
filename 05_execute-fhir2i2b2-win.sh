#!/bin/bash

export COMPOSE_PROJECT=num-knoten

winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=demouser i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources'"