# NUM-Knoten v2

Deployment package for the CODEX NUM-Knoten v2

## Current Version (NUM-Knoten v2.0)

![NUM-Knoten v2.0](img/num-codex-ap6-nk-v2.0.png)

Currently, this version is an early release for testing purposes and does not contain all of the planned components (e.g. no GECCO-Merger that merges parallel data pipelines from EDC and clinical source systems). Also, only parts of the pipeline support incremental loading. In further development, the whole pipelines is planned to be able to load data incrementally (Delta-Update).

## Final Version (NUM-Knoten v2 final)

![NUM-Knoten v2 final](img/num-codex-ap6-nk-v2-final.png)

This is the target architecture for the NUM-Knoten v2 containing also the possibility to transfer data from clinical systems or other sources and merge them with data from the EDC.

Note: The FHIR-GW also provides interfaces for Apache Kafka  and for filling a FHIR server with all resources in parallel (shown with dotted lines). Though, the default and official supported way is shown with solid lines.

## Deployment on Single Host

### System requirements

- [Git](https://git-scm.com/downloads) is required to clone this repository.
- [Docker Engine Release 19.03.0+](https://docs.docker.com/engine/install)
- [Docker Compose 1.27.0+](https://docs.docker.com/compose/install/) if you are not using Docker Desktop for Mac/Windows

We do not provide specific hardware requirements, but it is recommended to monitor the resource utilization of each component and scale out accordingly.

**IMPORTANT**: Make sure Docker gets enough memory. When using Windows, Docker is given only 2GB by default, which is not enough. Right-click on the docker symbol in the taskbar, go to "Resources" and set the memory to at least 8GB.

### Setup the Environment

Please be aware of the nginx setup described in section [Setup nginx](#setup-nginx). You can also disable provided nginx reverse proxy setup at all (or substitute with your own). Be aware, that by default all ports to the different interfaces are only exposed to localhost. (Compare regarding `docker-compose.yml` manifests)

`$ sh 00_setup-project-environment.sh <user> <password>`

This script generates a self-signed certificate for the node nginx and sets up one user to the basic auth access from outside localhost.
You can add more users or use your own certificate (see the [Setup nginx](#setup-nginx) section below).

Note: Please be aware that the selfsigned certificate needs a browser like Firefox that allows to bypass security warnings regarding invalid certificates.

### Start Environment

`$ sh 01_start-single-host-environment.sh`

### Stop and Delete Environment

**WARNING**: This also deletes all volumes, databases, pseudonym mappings and log files. Please make sure that you backup any information necessary before executing this script.

`$ sh 02_remove-single-host-environment.sh`

Note: Because of the multi component structure, there may arise some errors that state that the network cannot be removed because of active endpoints. Please ignore these error messages for now, as the network is nevertheless removed at the end of the script.

### Test from FHIR-GW on

You can test the pipeline without odm2fhir by sending a FHIR resource directly to the FHIR-GW REST API when the environment is up:

`$ sh 03_send-test-resource-to-fhir-gw.sh`

### Execute/Test from odm2fhir on

You can test the pipeline from EDC/odm2fhir on by simply executing odm2fhir when the environment is up:

`$ sh 04_execute-odm2fhir.sh`

Note: The default settings use test-data in odm2fhir. To execute with real data, please set up odm2fhir according to the documentation on <https://github.com/num-codex/odm2fhir/packages/496804>. (Which sould be 1) Setting both, `ODM_REDCAP_API_TOKEN` and `ODM_REDCAP_API_URL` according to your EDC and 2) Comment out line 18 in `odm2fhir/docker-compose.yml`)

### Test i2b2 data integration via "i2b2 FHIR Trigger Beta"

After odm2fhir terminated successfully, the fhir-to-i2b2 job can be set up and executed:

`$ sh 05_execute-fhir-to-i2b2.sh`

This should populate the i2b2 tables with data from the FHIR resources, in particular OBSERVATION_FACT, PATIENT_MAPPING, and PATIENT_DIMENSION. Also check table FHIR_ELT_LOG for potenial error messages.

You can also query these data with the i2b2 webclient. Go to i2b2 Webclient (see below for URL) with a browser, and log in with user "miracum" and password "demouser". Use your mouse/trackpad to click on "Login" (pressing the return key may not work). You can now query for e.g. "Diagnosen" or "Forschungsdatensatz GECCO => GECCO => Anamnese / Risikofaktoren", which should return a result other than zero, as shown in the screenshot below. Note that the patient count fluctuates for each query due to the obsfuscation built into i2b2 (to improve patient privacy). Not that queries for other concepts may not return a result ("< 3" is displayed) because the included test data does only provide a small number of entities.

![i2b2 Query Result](img/i2b2-result.png)

## Configuration

Generally you can set configuration environment variables by putting them in a `.env` file next to the according `docker-compose.yml` file in the component's subfolder.

Example (`odm2fhir/.env`):

```sh
ODM_REDCAP_API_TOKEN=ABCDEFGHIJKLMNOPQRSTUVWXYZ
ODM_REDCAP_API_URL=https://redcap.uk-mittelerde.de/api/
```

## URLs and Default Credentials

The following URLs work with access on the localhost. For access from outside, please be aware of the nginx setup (see also next sections).

| Component                    | URL                                              | Default User | Default Password |
|------------------------------|--------------------------------------------------|--------------|------------------|
| FHIR-GW API                  | <http://localhost:18080/fhir>                    | -            | -                |
| FHIR-GW DB JDBC              | <jdbc:postgresql://localhost:15432/fhir>         | postgres     | postgres         |
| gPAS SOAP API                | <http://localhost:18081/gpas/gpasService?wsdl>   | -            | -                |
| gPAS Domain Service SOAP API | <http://localhost:18081/gpas/DomainService?wsdl> | -            | -                |
| gPAS Web UI                  | <http://localhost:18081/gpas-web>                | -            | -                |
| i2b2 Web UI                  | <http://localhost/webclient/>                    | miracum      | demouser         |
| i2b2 DB JDBC                 | <jdbc:postgresql://localhost:25432/i2b2>         | i2b2         | demouser         |
| FHIR Server                  | <http://localhost:8081/fhir>                     | -            | -                |

## nginx Setup URLs and Default Credentials

These are the URLs for access to the webclients via nginx.

| Component   | URL                              | Default User | Default Password |
|-------------|----------------------------------|--------------|------------------|
| FHIR-GW API | <https://localhost/fhir-gw/fhir> | -            | -                |
| gPAS Web UI | <https://localhost/gpas-web>     | -            | -                |
| i2b2 Web UI | <https://localhost/i2b2>         | miracum      | demouser         |
| FHIR Server | <https://localhost/fhir>         | -            | -                |

For the URLs above, substitude "localhost" with your server ip or domain accordingly.
The nginx setup protects the node with HTTP basic auth. This has to be configured and users need to be created accordingly (see Setup nginx below).

## Setup nginx

### Using your own nginx

You can also setup your own reverse proxy. To disable the default nginx, set the  environment variable `NGINX_PROXY_ENABLED` to `false` before exexuting the `$ sh 01_start-single-host-environment.sh` script.

In case you have already started up the environment, execute `$ sh 02_remove-single-host-environment.sh` and then execute `$ sh 01_start-single-host-environment.sh` again.

### Add your own certificate

This project generates its own (self-signed) certificate for the nginx to use. This certificate is needed to enable https for the nginx and encrypt the communication. For productive deployment, the certificate should be subsituted with an own trusted certificate. To do this, follow these steps:

1. Exchange the `cert.pem` and `key.pem` files in the `node-rev-proxy` direcotry for your own (Ensure that the file names stay the same)
2. Execute the `$ sh reset-nginx.sh`

### Add additional users

To add additional users go into the `node-rev-proxy` directory of this repository `$ cd node-rev-proxy`
and exexute the `$ sh add-nginx-user.sh <user> <password>`. This adds a user to the `.htpasswd` file, which is mounted into the nginx.

## Choose a FHIR Server

This repository allows you to choose between two FHIR Servers (HAPI and Blaze). To configure which one to use, set the `FHIR_SERVER` variable accordingly, to either `hapi`or `blaze`. The default server is HAPI.

## Clear FHIR-DB

If necessary, the FHIR-DB can be cleared by truncating the PostgreSQL database's table 'resources'. Therefore use the following script:

`$ sh 06_clear-fhir-db.sh`
