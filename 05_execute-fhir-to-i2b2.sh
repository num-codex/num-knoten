#!/bin/sh

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Create Foreign Data Wrapper to FHIR-DB...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Creating i2b2 FHIR Trigger...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2-FHIR-Trigger.sql"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Loading i2b2 Ontology...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2Ontology.sql"
docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=demouser i2b2-pg sh -c "echo '### Running Postprocessing.sql...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources'"

# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Create Foreign Data Wrapper to FHIR-DB...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/create-fdw.sql"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Creating i2b2 FHIR Trigger...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2-FHIR-Trigger.sql"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=postgres i2b2-pg sh -c "echo '### Loading i2b2 Ontology...'; psql -U postgres -d i2b2 -a -f /fhir-to-i2b2/i2b2Ontology.sql"
# winpty docker-compose -p $COMPOSE_PROJECT -f i2b2/docker-compose.yml exec -e PGPASSWORD=demouser i2b2-pg sh -c "echo '### Running Postprocessing.sql...'; psql -U postgres -d i2b2 -a -c 'insert into i2b2miracum.fhir(fhir) select data from i2b2miracum.resources'"
