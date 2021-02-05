#!/bin/sh
echo ">>>Running prescript"
psql -U postgres -d i2b2 -a -f /i2b2-FHIR-Trigger.sql
psql -U postgres -d i2b2 -a -f /i2b2Ontology.sql
psql -U postgres -d i2b2 -a -f /Postprocessing.sql
