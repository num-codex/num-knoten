# NUM-Knoten v2

This repository contains the deployment package for the CODEX NUM-Knoten.

Currently, this is v1.9beta and does contain all of the planned components (e.g. no GECCO-Merger that merges data from EDC and clinical source systems).

![NUM-Knoten v1.9beta](img/num-codex-ap6-nk1.9beta_v5.png)

## Deployment on single host

### Start

`$ sh 01_start-single-host-environment.sh`

### Stop

`$ sh 03_stop-single-host-environment.sh`

### Test

#### Test from odm2fhir on

tbd

#### Test from FHIR-GW on

`$ sh 02_send-test-resource.sh`

### URLs and Default Credentials

| Component                    | URL                                              | Default User | Default Password |
|------------------------------|--------------------------------------------------|--------------|------------------|
| FHIR-GW API                  | <http://localhost:18080/fhir>                    | -            | -                |
| FHIR-GW DB JDBC              | <jdbc:postgresql://localhost:15432/fhir>         | postgres     | postgres         |
| gPAS SOAP API                | <http://localhost:18081/gpas/gpasService?wsdl>   | -            | -                |
| gPAS Domain Service SOAP API | <http://localhost:18081/gpas/DomainService?wsdl> | -            | -                |
| gPAS Web UI                  | <http://localhost:18081/gpas-web>                | -            | -                |
| i2b2 Web UI                  | <http://localhost/webclient/>                    | miracum      | demouser         |
| i2b2 DB JDBC                 | <jdbc:postgresql://localhost:25432/i2b2>         | i2b2         | demouser         |
