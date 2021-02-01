CREATE EXTENSION postgres_fdw;

GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO i2b2;

CREATE SERVER fhir_db_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (dbname 'fhir', host 'fhir-db', port '5432');

CREATE USER MAPPING FOR i2b2
    SERVER fhir_db_server
    OPTIONS (USER 'postgres', PASSWORD 'postgres');

CREATE FOREIGN TABLE i2b2miracum.resources(id SERIAL NOT NULL,
    fhir_id VARCHAR(64) NOT NULL,
    type VARCHAR(64) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL,
    last_updated_at TIMESTAMP DEFAULT NOW() NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE NOT NULL)
    SERVER fhir_db_server
    OPTIONS (SCHEMA_NAME 'public', TABLE_NAME 'resources');
