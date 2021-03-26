#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Creating Foreign Data Wrapper to FHIR-DB ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Creating i2b2 FHIR Trigger ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2-FHIR-Trigger.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Loading i2b2 Ontology ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2Ontology.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/Postprocessing.sql > /dev/null"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Executing actual ETL ...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources' > /dev/null"

# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Creating Foreign Data Wrapper to FHIR-DB ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql > /dev/null"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Creating i2b2 FHIR Trigger ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2-FHIR-Trigger.sql > /dev/null"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Loading i2b2 Ontology ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2Ontology.sql > /dev/null"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Running Postprocessing.sql ...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/Postprocessing.sql > /dev/null"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec i2b2-pg sh -c "echo '### Executing actual ETL ...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources' > /dev/null"
