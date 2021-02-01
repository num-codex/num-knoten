#!/bin/bash

export COMPOSE_PROJECT=num-knoten

docker-compose -p $COMPOSE_PROJECT -f odm2fhir/docker-compose.yml up
