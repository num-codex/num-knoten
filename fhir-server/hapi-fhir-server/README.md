> ⚠ No longer updated. Consider using the official sample project this is based on instead: <https://github.com/hapifhir/hapi-fhir-jpaserver-starter>

# HAPI FHIR Server

Simple HAPI FHIR Server based on the [jpaserver starter repository](https://github.com/hapifhir/hapi-fhir-jpaserver-starter).

Supporting DSTU3 and R4.

## Run

### With batteries included

```sh
docker-compose -f docker-compose.yml up
```

Access at <http://localhost:8082/fhir.>

### Only image (runs with an in-memory H2 database)

```sh
docker run -p 8080:8080 docker.miracum.org/miracum-data/hapi-fhir-jpaserver:v8.1.3
```

### Running behind a reverse proxy

Some resource fields require the fully qualified URL of the server in order to work properly, e.g. the `link` field in a search result to support paging.
By default, the server tries to figure out what URL to put there based on the host header of the HTTP request. This requires that the host header is
passed to the FHIR server from the reverse proxy. However, this approach currently ignores the protocol and defaults to `http` to use `https`, you
will need to manually set the URL via the `server.address.override` environment variable, see [#4](https://gitlab.miracum.org/miracum/hapi-fhir-server/issues/4).

## Configure

All configuration options listed in the [hapi.properties file](src/main/resources/hapi.properties) can be overriden as environment variables.

## Build

```sh
docker build -t hapi-fhir-jpaserver:local .
```
