# NUM-Knoten v2

This repository contains the deployment package for the CODEX NUM-Knoten.

## Deployment on single host

### Start

`$ sh start-single-host-environment.sh`

### Stop

`$ sh stop-single-host-environment.sh`

### URLs

|                                       |                                                |
|---------------------------------------|------------------------------------------------|
| FHIR-GW API URL                       | <http://localhost:18080/fhir>                  |
| FHIR-GW DB JDBC URL                   | <jdbc:postgresql://localhost:15432/fhir>       |
| gPAS SOAP API Endpoint                | <http://localhost:18081/gpas/gpasService?wsdl> |
| gPAS Domain Service SOAP API Endpoint | <http://localhost:18081/gpas/DomainService>    |
| gPAS Web UI                           | <http://localhost:18081/gpas-web>              |
| i2b2 Web UI                           | <http://localhost:380/webclient/>              |
