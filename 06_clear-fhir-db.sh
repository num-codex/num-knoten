#!/bin/sh

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f fhir-gw/docker-compose.yml exec -e PGPASSWORD=postgres fhir-db sh -c "psql -U postgres -d fhir -a <<EOF
\x
TRUNCATE TABLE public.resources;
EOF"
