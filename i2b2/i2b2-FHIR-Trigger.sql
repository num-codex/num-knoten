-- ==================================================================================
-- i2b2-FHIR-Trigger - Load incoming FHIR data into i2b2 schema via database triggers
-- ==================================================================================

-- Author: Sebastian Mate (sebastian.mate@uk-erlangen.de)

-- Revision History:
-- -----------------
-- 2021-01-22: - Add additional test data (in the comment block at the end of the file) so that i2b2 returns a patient count
-- 2021-01-25: - Initial basic support for FHIR bundles
--             - Improved readout of Patient resource
-- 2021-01-26: - Use now() when no date is specified (Observation, Procedure)
--			   - Implemented "MedicationStatement" compatibility with GECCO data from odm2fhir
--			   - Generation of system identifier abbreviations now handled in function get_system_abbrv()
--			   - Initial support for resource type "Immunization"
-- 2021-01-27: - Add support for various ways of patient-referencing for GECCO resources
--			   - Initial support for resource type "Consent"
--			   - Note: Implementation of "Immunization" and "Consent" useless, as-is. TODO
-- 2021-01-28: - Reimplementation of "Condition" resource processing to make it compatible with GECCO modeling
-- 2021-01-29: - Achieve backward-compatibility with PostgreSQL 9.4 (old Miracum i2b2 Deployment)
--			   - For start_date and end_date, instead of now(), use '-infinity'::timestamptz if no timestamp could be determined
--			   - Reimplementation of "Observation" resource processing to make it compatible with GECCO modeling
--			   - Reimplementation of "Procedure" resource processing to make it compatible with GECCO modeling
-- 2021-02-01: - Add support for "bodySite" field in "Procedure" ressource
--			   - Implementation of support for "DiagnosticReport" resource
--			   - Implementation of support for "Immunization" resource
--			   - Update implementation for "Consent" resource
--			   - Update implementation for "MedicationStatement" resource
--             - FIRST RELEASE FOR NUM CODEX

-- ============= Create Basic Tables =============

-- Create the "fhir" table, which will act as the "inbox" for the FHIR data:
drop table if exists i2b2miracum.fhir;
create table i2b2miracum.fhir (fhir jsonb null);
create index idx_fhir_patient_identifier_value on i2b2miracum.fhir using btree (((fhir->'identifier'::text)->>'value'::text));
create index idx_fhir_resourcetype on i2b2miracum.fhir using btree ((fhir->>'resourceType'::text));

-- Create the "fhir_failed" table, used to dump failing data (WIP):
drop table if exists i2b2miracum.fhir_failed;
create table i2b2miracum.fhir_failed (ts timestamptz null, message text null, fhir jsonb null);

drop table if exists i2b2miracum.fhir_medication;
create table i2b2miracum.fhir_medication (id text, code text, system text, display text);

-- Create the "fhir_elt_log" table, which log messages:
drop table if exists i2b2miracum.fhir_elt_log;
create table i2b2miracum.fhir_elt_log (ts timestamptz null,	message text null);

-- Create the "fhir_elt_log" function, which can be used to log these massages:
create or replace function i2b2miracum.fhir_elt_log(message text) returns void language plpgsql as
$$
begin
	insert into i2b2miracum.fhir_elt_log (ts, message) values (current_timestamp, "message");
end;
$$;

-- Clear i2b2 database:
truncate table i2b2miracum.patient_mapping;
truncate table i2b2miracum.patient_dimension;
truncate table i2b2miracum.encounter_mapping;
truncate table i2b2miracum.observation_fact;
truncate table i2b2miracum.fhir_elt_log;

-- Modify OBSERVATION_FACT:
do $$ 
	begin
		alter table i2b2miracum.observation_fact add fhir_reference varchar(100) null;
	exception
		when duplicate_column then raise notice 'Column already exists.';
	end;
$$;

--CREATE INDEX observation_fact_observation_blob_idx ON i2b2miracum.observation_fact (observation_blob);
--CREATE INDEX observation_fact_fhir_reference_idx ON i2b2miracum.observation_fact (fhir_reference);

-- Create OBSERVATION_FACT_TEMP, which will be used to store temporary data:
drop table if exists i2b2miracum.observation_fact_temp;
create table i2b2miracum.observation_fact_temp as (select * from i2b2miracum.observation_fact);

-- Create and Initialize PATIENT_NUM up-counter:
drop sequence if exists patient_num_seq;
create sequence patient_num_seq; 
select setval('patient_num_seq', (select max(patient_num) from i2b2miracum.patient_mapping), true);

-- Create and Initialize ENCOUNTER_NUM up-counter:
drop sequence if exists encounter_num_seq;
create sequence encounter_num_seq; 
select setval('encounter_num_seq', (select max(encounter_num) from i2b2miracum.encounter_mapping), true);

-- Create and Initialize INSTANCE_NUM up-counter:
drop sequence if exists instance_num_seq;
create sequence instance_num_seq; 
select setval('instance_num_seq', (select max(instance_num) from i2b2miracum.observation_fact), true);

-- Create the "get_system_abbrv" function that abbreviates long system identifiers:
create or replace function i2b2miracum.get_system_abbrv(systemlink text) returns text language plpgsql as
$$
begin
	case when systemlink = 'http://fhir.de/CodeSystem/dimdi/icd-10-gm' then return 'ICD10';
	     when systemlink = 'http://fhir.de/CodeSystem/dimdi/ops' then return 'OPS';
	     when systemlink = 'http://fhir.de/CodeSystem/dimdi/atc' then return 'ATC';
	     when systemlink = 'http://snomed.info/sct' then return 'SNOMED-CT';
		 when systemlink = 'http://loinc.org' then return 'LOINC';
		 when systemlink = 'urn:oid:2.16.840.1.113883.6.18.2.6' then return 'PRODUCT-TYPE';
		 when systemlink = 'https://www.netzwerk-universitaetsmedizin.de/fhir/CodeSystem/ecrf-parameter-codes' then return 'ECRF';
		 when systemlink = 'http://fdasis.nlm.nih.gov' then return 'FDASIS';
		 when systemlink = 'http://dicom.nema.org/resources/ontology/DCM' then return 'DCM';
		 when systemlink = 'http://terminology.hl7.org/CodeSystem/condition-ver-status' then return 'CVS';
		 when systemlink = 'http://terminology.hl7.org/CodeSystem/consentcategorycodes' then return 'CCC';
	else 
		 perform i2b2miracum.fhir_elt_log('ERROR: Coding system unknown: ' || systemlink);
		 return 'UNKNOWN';
	end case;
end;
$$;

-- ============= i2b2 FHIR Trigger =============

-- Create the "fhir_inserted" function that is called each time a new FHIR resource is inserted:
create or replace function i2b2miracum.fhir_inserted() returns trigger language plpgsql as
$$
declare
	element text;
    i record;
begin
	--
	perform i2b2miracum.fhir_elt_log('--- Incoming FHIR: ' || new.fhir::text);
	--
	if json_extract_path_text(new.fhir::json, 'resourceType') = 'Bundle' then
		--for i in select * from jsonb_array_elements(new.fhir->'entry')
		for i in (select jsonb_array_elements(new.fhir->'entry') element)
		loop
			perform i2b2miracum.process_fhir_resource(i.element->'resource');
		end loop;
	else
		perform i2b2miracum.process_fhir_resource(new.fhir);
	end if;
	--
	return null; -- Return nothing. This prevents that the FHIR data is actually written into the "FHIR" table.
exception 
	when others then
		perform i2b2miracum.fhir_elt_log('ERROR: Exception cought: ' || sqlerrm);
		insert into i2b2miracum.fhir_failed(ts, message, fhir) values (now(), sqlerrm, new.fhir);
		return null;
end;
$$;

create or replace function i2b2miracum.process_fhir_resource(fhir jsonb) returns void language plpgsql as
$$
declare
	FHIR_id text := fhir->>'id';
	FHIR_resourcetype text := json_extract_path_text(fhir::json, 'resourceType');
	FHIR_sourcesystem text := fhir->'meta'->>'source';
	FHIR_patient_identifier text; -- Use the resource ID if patient identifier ist not specified otherwise.
	FHIR_patient_identifier_GECCO text := fhir->'subject'->>'reference'; -- Fallback GECCO
	FHIR_patient_identifier_GECCO_ImmunCons1 text := fhir->'patient'->'identifier'->>'value'; -- Fallback GECCO Immunization/Consent
	FHIR_patient_identifier_GECCO_ImmunCons2 text := fhir->'patient'->>'reference'; -- Fallback GECCO Immunization/Consent (variant 2)
	FHIR_encounter_identifier text;
	i2b2_patient_identifier int; declare i2b2_patient_found int;
	i2b2_encounter_identifier int; declare i2b2_encounter_found int;
begin
	if FHIR_resourcetype != 'Bundle' and
	   FHIR_resourcetype != 'Patient' and
	   FHIR_resourcetype != 'Encounter' and
	   FHIR_resourcetype != 'Condition' and
	   FHIR_resourcetype != 'Observation' and
	   FHIR_resourcetype != 'Immunization' and -- TODO
   	   FHIR_resourcetype != 'Consent' and      -- TODO
	   FHIR_resourcetype != 'Procedure' and
	   FHIR_resourcetype != 'Medication' and
	   FHIR_resourcetype != 'MedicationStatement' and
	   FHIR_resourcetype != 'ServiceRequest' and -- Ignored, not useful for i2b2.
	   FHIR_resourcetype != 'DiagnosticReport'
    then raise exception 'Resource type "%" not supported.', FHIR_resourcetype; end if;
	--
	perform i2b2miracum.fhir_elt_log('--- Processing new ' || FHIR_resourcetype || ' resource:');
	--
	--
	if FHIR_resourcetype != 'Medication' then -- Skip all resources that do not contribute patient data.
		--
		-- Extract FHIR_patient_identifier and FHIR_encounter_identifier from FHIR resource:
		if FHIR_resourcetype = 'Patient' then
			-- Disable next line for GECCO:
			-- FHIR_patient_identifier := jsonb_array_elements(fhir->'identifier')->>'value';
			--
			if FHIR_patient_identifier is null then 
				-- raise exception 'FHIR_patient_identifier is empty!'; end if;
				FHIR_patient_identifier := 'Patient/' || FHIR_id;
			end if;
		else
			FHIR_patient_identifier := fhir->'subject'->'identifier'->>'value';
			--
			if FHIR_patient_identifier is null and FHIR_patient_identifier_GECCO is not null then
				FHIR_patient_identifier := FHIR_patient_identifier_GECCO;
			end if;
			--
			if FHIR_patient_identifier is null and FHIR_patient_identifier_GECCO_ImmunCons1 is not null then
				FHIR_patient_identifier := FHIR_patient_identifier_GECCO_ImmunCons1;
			end if;
			--
			if FHIR_patient_identifier is null and FHIR_patient_identifier_GECCO_ImmunCons2 is not null then
				FHIR_patient_identifier := FHIR_patient_identifier_GECCO_ImmunCons2;
			end if;
		end if;
		--
		if FHIR_resourcetype = 'Encounter' then
			FHIR_encounter_identifier := jsonb_array_elements(fhir->'identifier')->>'value';
			if FHIR_encounter_identifier is null then raise exception 'FHIR_encounter_identifier is empty!'; end if;
		else
			FHIR_encounter_identifier := fhir->'encounter'->'identifier'->>'value';
		end if;
		--
		if FHIR_resourcetype = 'MedicationStatement' then
			FHIR_encounter_identifier := fhir->'context'->'identifier'->>'value';
		end if;
		--
		if FHIR_patient_identifier is null then FHIR_patient_identifier := 'UNKNOWN'; end if;
		if FHIR_encounter_identifier is null then FHIR_encounter_identifier := 'UNKNOWN'; end if;
		perform i2b2miracum.fhir_elt_log('FHIR_patient_identifier = ' || FHIR_patient_identifier);
		perform i2b2miracum.fhir_elt_log('FHIR_encounter_identifier = ' || FHIR_encounter_identifier);
		--
		-- *** Handle i2b2 PATIENT data / references ***
		--
		-- Check if the patient is already known in i2b2:
		select patient_num into i2b2_patient_found from i2b2miracum.patient_mapping where patient_ide = FHIR_patient_identifier;
		--
		if i2b2_patient_found is not null then
			perform i2b2miracum.fhir_elt_log('Patient is aldready known in i2b2.');
			i2b2_patient_identifier := i2b2_patient_found;
			if FHIR_resourcetype = 'Patient' then
				perform i2b2miracum.fhir_elt_log('Deleting previous entries in PATIENT_MAPPING and PATIENT_DIMENSION.');
				delete from i2b2miracum.patient_dimension where patient_num in (select patient_num from i2b2miracum.patient_mapping where patient_ide = FHIR_patient_identifier);
				delete from i2b2miracum.patient_mapping where patient_ide = FHIR_patient_identifier;
			end if;
		else
			i2b2_patient_identifier := nextval('patient_num_seq');
			perform i2b2miracum.fhir_elt_log('Got new i2b2_patient_identifier = ' || i2b2_patient_identifier);
		end if;
		--
		if i2b2_patient_found is null or FHIR_resourcetype = 'Patient' then
			perform i2b2miracum.fhir_elt_log('Inserting into PATIENT_MAPPING.');
			-- Populate PATIENT_MAPPING:
			insert into i2b2miracum.patient_mapping (patient_ide,patient_ide_source,patient_num,patient_ide_status,project_id,upload_date,update_date,
													 download_date,import_date,sourcesystem_cd,upload_id)
			values (FHIR_patient_identifier, -- patient_ide
					'FHIR', -- patient_ide_source
					i2b2_patient_identifier, -- patient_num
					'A', -- patient_ide_status
					'Miracum', -- project_id
					now(), -- upload_date
					now(), -- update_date
					now(), -- download_date
					now(), -- import_date
					FHIR_sourcesystem, -- sourcesystem_cd
					1 -- upload_id
					);
			--
			if FHIR_resourcetype = 'Patient' then
				perform i2b2miracum.fhir_elt_log('Inserting into PATIENT_DIMENSION.');
				-- Populate PATIENT_DIMENSION:
				insert into i2b2miracum.patient_dimension (patient_num,vital_status_cd,birth_date,death_date,sex_cd,age_in_years_num,language_cd,race_cd,
				                                           marital_status_cd,religion_cd,zip_cd,statecityzip_path,income_cd,patient_blob,update_date,
				                                           download_date,import_date,sourcesystem_cd,upload_id)
				select  i2b2_patient_identifier, -- patient_num
						case when fhir_data.deceasedDateTime is not null then 'Y'
							 else 'N' end, -- vital_status_cd
						fhir_data.birthDate, -- birth_date
						fhir_data.deceasedDateTime, -- death_date
						case when fhir_data.gender = 'male' then 'm'
						     when fhir_data.gender = 'female' then 'f'
		   				     when fhir_data.gender = 'other' then 'd'
		   				     when fhir_data.gender = 'unknown' then 'x'
						     else null end, -- sex_cd
						case when fhir_data.deceasedDateTime is null then extract(year from age(now(), fhir_data.deceasedDateTime))
						     else extract(year from age(fhir_data.deceasedDateTime, fhir_data.birthDate)) end, -- age_in_years_num
						null, -- language_cd
						null, -- race_cd
						null, -- marital_status_cd
						null, -- religion_cd
						address_postalCode, -- zip_cd
						null, -- statecityzip_path
						null, -- income_cd
						null, -- patient_blob
						now(), -- update_date
						now(), -- download_date
						now(), -- import_date
						FHIR_sourcesystem, -- sourcesystem_cd
						1  -- upload_id
			  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					birthDate,
					deceasedDateTime,
					gender,
					address_postalCode
				from FhirTempTable
				left join (select (fhir2->>'birthDate')::timestamp as birthDate
							 from FhirTempTable) as sq1 on true
				left join (select (fhir2->>'deceasedDateTime')::timestamp as deceasedDateTime
							 from FhirTempTable) as sq2 on true
				left join (select (fhir2->>'gender')::text as gender
							 from FhirTempTable) as sq3 on true
				left join (select  jsonb_array_elements(fhir2->'address')->>'postalCode' as address_postalCode
							 from FhirTempTable) as sq4 on true
		      ) fhir_data;						
			end if;
		end if;
		--
		-- *** Handle i2b2 ENCOUNTER data / references ***
		--
		if FHIR_resourcetype != 'Patient' then
			-- Check if the encounter is already known in i2b2:
			select encounter_num into i2b2_encounter_found from i2b2miracum.encounter_mapping where encounter_ide = FHIR_encounter_identifier;
			--
			if i2b2_encounter_found is not null then
				perform i2b2miracum.fhir_elt_log('Encounter is aldready known in i2b2.');
				i2b2_encounter_identifier := i2b2_encounter_found;
				if FHIR_resourcetype = 'Encounter' then
					perform i2b2miracum.fhir_elt_log('Deleting previous entry in ENCOUNTER_MAPPING.');
					delete from i2b2miracum.encounter_mapping where encounter_ide = FHIR_encounter_identifier;
				end if;
			else
				i2b2_encounter_identifier := nextval('encounter_num_seq');
				perform i2b2miracum.fhir_elt_log('Got new i2b2_encounter_identifier = ' || i2b2_encounter_identifier);
			end if;
			--
			if i2b2_encounter_found is null or FHIR_resourcetype = 'Encounter' then
				perform i2b2miracum.fhir_elt_log('Inserting into ENCOUNTER_MAPPING.');
				-- Populate ENCOUNTER_MAPPING:
				insert into i2b2miracum.encounter_mapping (encounter_ide, encounter_ide_source, project_id, encounter_num, patient_ide, patient_ide_source, encounter_ide_status, upload_date, update_date, download_date, import_date, sourcesystem_cd, upload_id)
				values (FHIR_encounter_identifier, -- encounter_ide
						'FHIR', -- encounter_ide_source
						'Miracum', -- project_id
						i2b2_encounter_identifier, -- encounter_num
						FHIR_patient_identifier, -- patient_ide
						'FHIR', -- patient_ide_source
						'A', -- encounter_ide_status
						now(), -- upload_date
						now(), -- update_date
						now(), -- download_date
						now(), -- import_date
						FHIR_sourcesystem, -- sourcesystem_cd
						1 -- upload_id
				);
			end if;
		end if;
	end if;
	--
	-- *** Handle FHIR CONDITION resource ***
	--
	if FHIR_resourcetype = 'Condition' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd,	instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
			 	i2b2miracum.get_system_abbrv(fhir_data.code_coding_system) || ':' || fhir_data.code_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.OnsetDateTime is not null then fhir_data.OnsetDateTime
					 else '-infinity'::timestamptz
					 end, -- start_date
				case when fhir_data.verificationStatus_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.verificationStatus_coding_system) || ':' || fhir_data.verificationStatus_coding_code
				 	 when fhir_data.extension_valueCodeableConcept_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.extension_valueCodeableConcept_coding_system) || ':' || fhir_data.extension_valueCodeableConcept_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'@', -- valtype_cd
				null, -- tval_char
				null, -- nval_num
				null, -- valueflag_cd
				null, -- quantity_num
				null, -- units_cd
				case when fhir_data.OnsetDateTime is not null then fhir_data.OnsetDateTime
					 else '-infinity'::timestamptz
					 end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					OnsetDateTime,
					code_coding_code,
					code_coding_system,
					verificationStatus_coding_code,
					verificationStatus_coding_system,
					extension_valueCodeableConcept_coding_code,
					extension_valueCodeableConcept_coding_system
				from FhirTempTable
				left join (select (fhir2->>'recordedDate')::timestamp as OnsetDateTime
							 from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'code'->'coding')->>'code' as code_coding_code,
		  						  jsonb_array_elements(fhir2->'code'->'coding')->>'system' as code_coding_system
							 from FhirTempTable) as sq2 on true
				left join (select jsonb_array_elements(fhir2->'verificationStatus'->'coding')->>'code' as verificationStatus_coding_code,
								  jsonb_array_elements(fhir2->'verificationStatus'->'coding')->>'system' as verificationStatus_coding_system
							 from FhirTempTable) as sq3 on true
				left join (select jsonb_array_elements(jsonb_array_elements(fhir2->'extension')->'valueCodeableConcept'->'coding')->>'code' as extension_valueCodeableConcept_coding_code,
								  jsonb_array_elements(jsonb_array_elements(fhir2->'extension')->'valueCodeableConcept'->'coding')->>'system' as extension_valueCodeableConcept_coding_system
							 from FhirTempTable) as sq4 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle FHIR OBSERVATION resource ***
	--
	if FHIR_resourcetype = 'Observation' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				i2b2miracum.get_system_abbrv(fhir_data.code_coding_system) || ':' || fhir_data.code_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
					 when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- start_date
				case when fhir_data.valueCodeableConcept_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.valueCodeableConcept_coding_system) || ':' || fhir_data.valueCodeableConcept_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'N', -- valtype_cd
				'E', -- tval_char
				fhir_data.valueQuantity_value, -- nval_num
				'', -- valueflag_cd
				1, -- quantity_num
				fhir_data.valueQuantity_unit, -- units_cd
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
					 when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
				from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					performedDateTime,
					code_coding_code,
					code_coding_system,
					valueQuantity_value,
					valueQuantity_unit,
					valueQuantity_system,
					valueQuantity_code,
					valueCodeableConcept_coding_code,
					valueCodeableConcept_coding_system,
					effectiveDateTime
				from FhirTempTable
				left join (select (fhir2->>'performedDateTime')::timestamp as performedDateTime
							 from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'code'->'coding')->>'code' as code_coding_code,
		  						  jsonb_array_elements(fhir2->'code'->'coding')->>'system' as code_coding_system
							 from FhirTempTable) as sq2 on true
				left join (select (fhir2->'valueQuantity'->>'value')::numeric(18,5) as valueQuantity_value,
		  						  fhir2->'valueQuantity'->>'unit'::text as valueQuantity_unit,
		  						  fhir2->'valueQuantity'->>'system'::text as valueQuantity_system,
		  						  fhir2->'valueQuantity'->>'code'::text as valueQuantity_code
							 from FhirTempTable) as sq3 on true
				left join (select jsonb_array_elements(fhir2->'valueCodeableConcept'->'coding')->>'code' as valueCodeableConcept_coding_code,
		  						  jsonb_array_elements(fhir2->'valueCodeableConcept'->'coding')->>'system' as valueCodeableConcept_coding_system
							 from FhirTempTable) as sq4 on true
 				left join (select (fhir2->>'effectiveDateTime')::timestamp as effectiveDateTime
							 from FhirTempTable) as sq5 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle GECCO FHIR Immunization resource ***
	--
	if FHIR_resourcetype = 'Immunization' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				/*'VACC:' || */i2b2miracum.get_system_abbrv(fhir_data.protocolApplied_targetDisease_coding_system) || ':' || fhir_data.protocolApplied_targetDisease_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
				     else '-infinity'::timestamptz end, -- start_date
				case when fhir_data.vaccineCode_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.vaccineCode_coding_system) || ':' || fhir_data.vaccineCode_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'N', -- valtype_cd
				'E', -- tval_char
				null, -- nval_num
				'', -- valueflag_cd
				1, -- quantity_num
				null, -- units_cd
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					performedDateTime,
					vaccineCode_coding_code,
					vaccineCode_coding_system,
					protocolApplied_targetDisease_coding_code,
					protocolApplied_targetDisease_coding_system
				from FhirTempTable
				left join (select (fhir2->>'performedDateTime')::timestamp as performedDateTime
			 			   from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'vaccineCode'->'coding')->>'code' as vaccineCode_coding_code,
		  				          jsonb_array_elements(fhir2->'vaccineCode'->'coding')->>'system' as vaccineCode_coding_system
						   from FhirTempTable) as sq2 on true
				left join (select jsonb_array_elements(jsonb_array_elements(jsonb_array_elements(fhir2->'protocolApplied')->'targetDisease')->'coding')->>'code' as protocolApplied_targetDisease_coding_code,
		  				          jsonb_array_elements(jsonb_array_elements(jsonb_array_elements(fhir2->'protocolApplied')->'targetDisease')->'coding')->>'system' as protocolApplied_targetDisease_coding_system
						   from FhirTempTable) as sq3 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle GECCO FHIR Consent resource ***
	--
	if FHIR_resourcetype = 'Consent' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				i2b2miracum.get_system_abbrv(fhir_data.category_coding_system) || ':' || fhir_data.category_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- start_date
				case when fhir_data.provision_code_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.provision_code_coding_system) || ':' || fhir_data.provision_code_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'N', -- valtype_cd
				'E', -- tval_char
				null, -- nval_num
				'', -- valueflag_cd
				1, -- quantity_num
				null, -- units_cd
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					effectiveDateTime,
					category_coding_code,
					category_coding_system,
					provision_code_coding_code,
					provision_code_coding_system
				from FhirTempTable
				left join (select (fhir2->>'effectiveDateTime')::timestamp as effectiveDateTime
			 			   from FhirTempTable) as sq1 on true
   				left join (select jsonb_array_elements(jsonb_array_elements(fhir2->'category')->'coding')->>'code' as category_coding_code,
								  jsonb_array_elements(jsonb_array_elements(fhir2->'category')->'coding')->>'system' as category_coding_system
 					  	   from FhirTempTable) as sq2 on true
				left join (select jsonb_array_elements(jsonb_array_elements(fhir2->'provision'->'code')->'coding')->>'code' as provision_code_coding_code,
								  jsonb_array_elements(jsonb_array_elements(fhir2->'provision'->'code')->'coding')->>'system' as provision_code_coding_system
			 			   from FhirTempTable) as sq3 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle FHIR PROCEDURE resource ***
	--
	if FHIR_resourcetype = 'Procedure' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				i2b2miracum.get_system_abbrv(fhir_data.code_coding_system) || ':' || fhir_data.code_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
				     else '-infinity'::timestamptz end, -- start_date
				case when fhir_data.bodySite_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.bodySite_coding_system) || ':' || fhir_data.bodySite_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'@', -- valtype_cd
				null, -- tval_char
				null, -- nval_num
				null, -- valueflag_cd
				null, -- quantity_num
				null, -- units_cd
				case when fhir_data.performedDateTime is not null then fhir_data.performedDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					performedDateTime,
					code_coding_code,
					code_coding_system,
					bodySite_coding_code,
					bodySite_coding_system					
				from FhirTempTable
				left join (select (fhir2->>'performedDateTime')::timestamp as performedDateTime
							 from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'code'->'coding')->>'code' as code_coding_code,
		  						  jsonb_array_elements(fhir2->'code'->'coding')->>'system' as code_coding_system
							 from FhirTempTable) as sq2 on true
				left join (select jsonb_array_elements(jsonb_array_elements(fhir2->'bodySite')->'coding')->>'code' as bodySite_coding_code,
		  						  jsonb_array_elements(jsonb_array_elements(fhir2->'bodySite')->'coding')->>'system' as bodySite_coding_system
							 from FhirTempTable) as sq3 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle FHIR DIAGNOSTICREPORT resource ***
	--
	if FHIR_resourcetype = 'DiagnosticReport' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				i2b2miracum.get_system_abbrv(fhir_data.code_coding_system) || ':' || fhir_data.code_coding_code, -- concept_cd
				'FHIR', -- provider_id
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- start_date
				case when fhir_data.conclusionCode_coding_system is not null 
					 	then i2b2miracum.get_system_abbrv(fhir_data.conclusionCode_coding_system) || ':' || fhir_data.conclusionCode_coding_code
					 else '@'
					 end, -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'@', -- valtype_cd
				null, -- tval_char
				null, -- nval_num
				null, -- valueflag_cd
				null, -- quantity_num
				null, -- units_cd
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq') -- text_search_index
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					effectiveDateTime,
					code_coding_code,
					code_coding_system,
					conclusionCode_coding_code,
					conclusionCode_coding_system					
				from FhirTempTable
				left join (select (fhir2->>'effectiveDateTime')::timestamp as effectiveDateTime
							 from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'code'->'coding')->>'code' as code_coding_code,
		  						  jsonb_array_elements(fhir2->'code'->'coding')->>'system' as code_coding_system
							 from FhirTempTable) as sq2 on true
				left join (select jsonb_array_elements(jsonb_array_elements(fhir2->'conclusionCode')->'coding')->>'code' as conclusionCode_coding_code,
		  						  jsonb_array_elements(jsonb_array_elements(fhir2->'conclusionCode')->'coding')->>'system' as conclusionCode_coding_system
							 from FhirTempTable) as sq3 on true
		      ) fhir_data;
	end if;
	--
	-- *** Handle FHIR MEDICATION resource ***
	--
	if FHIR_resourcetype = 'Medication' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in FHIR_MEDICATION.');
		delete from i2b2miracum.fhir_medication where id = FHIR_id;
		-- Store Medication information in separate table FHIR_MEDICATION:
		perform i2b2miracum.fhir_elt_log('Inserting into FHIR_MEDICATION.');
		insert into i2b2miracum.fhir_medication (id, code, system, display)
		select  FHIR_id,
				fhir_data.code,
				fhir_data.system,
				fhir_data.display
		  from (SELECT 
		        jsonb_array_elements(new_as_table.fhir->'code'->'coding')->>'code' as code,
		  		jsonb_array_elements(new_as_table.fhir->'code'->'coding')->>'system' as system,
		  		jsonb_array_elements(new_as_table.fhir->'code'->'coding')->>'display' as display
		  		from (select fhir) new_as_table 
		  	) fhir_data;
		-- Update old MedicationStatement data in OBSERVATION_FACT
		-- Move the old OBSERVATION_FACT entry (MedicationStatement data) to OBSERVATION_FACT_TEMP:
		insert into i2b2miracum.observation_fact_temp (select * from i2b2miracum.observation_fact where fhir_reference = 'Medication/' || FHIR_id);
		delete from i2b2miracum.observation_fact where fhir_reference = 'Medication/' || FHIR_id;
		insert into i2b2miracum.observation_fact (
			select 	oft.encounter_num,
					oft.patient_num,
					i2b2miracum.get_system_abbrv(fm.system) || ':' || fm.code, -- concept_cd
					oft.provider_id,
					oft.start_date,
					oft.modifier_cd,
					oft.instance_num,
					oft.valtype_cd,
					oft.tval_char,
					oft.nval_num,
					oft.valueflag_cd,
					oft.quantity_num,
					oft.units_cd,
					oft.end_date,
					oft.location_cd,
					oft.observation_blob,
					oft.confidence_num,
					oft.update_date,
					oft.download_date,
					oft.import_date,
					oft.sourcesystem_cd,
					oft.upload_id,
					nextval('instance_num_seq') as text_search_index,
					oft.fhir_reference
			from i2b2miracum.observation_fact_temp oft, i2b2miracum.fhir_medication fm 
			where oft.fhir_reference = 'Medication/' || FHIR_id
			  and oft.fhir_reference = 'Medication/' || fm.id
		);
		truncate table i2b2miracum.observation_fact_temp;
	--
	end if;
	--
	-- *** Handle FHIR MEDICATIONSTATEMENT resource ***
	--
	if FHIR_resourcetype = 'MedicationStatement' then
		-- Delete previous data:
		perform i2b2miracum.fhir_elt_log('Deleting previous entries in OBSERVATION_FACT.');
		delete from i2b2miracum.observation_fact where observation_blob = FHIR_id;
		-- Insert new data:
		perform i2b2miracum.fhir_elt_log('Inserting into OBSERVATION_FACT.');
		insert into i2b2miracum.observation_fact (encounter_num, patient_num, concept_cd, provider_id, start_date, modifier_cd, instance_num, valtype_cd, tval_char, nval_num, valueflag_cd, quantity_num, units_cd, end_date, location_cd, observation_blob, confidence_num, update_date, download_date, import_date, sourcesystem_cd, upload_id, text_search_index, fhir_reference)
		select  i2b2_encounter_identifier, -- encounter_num
				i2b2_patient_identifier, -- patient_num
				case when fhir_data.medicationCodeableConcept_coding_code is not null then 
		 				 i2b2miracum.get_system_abbrv(fhir_data.medicationCodeableConcept_coding_system) || ':' || fhir_data.medicationCodeableConcept_coding_code
					 when fhir_data.medication_code is not null then
		 				 i2b2miracum.get_system_abbrv(fhir_data.medication_system) || ':' || fhir_data.medication_code
					 else
					 	'Medication'
				end,
				'FHIR', -- provider_id
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- start_date
				'@', -- modifier_cd
				nextval('instance_num_seq'), -- instance_num
				'@', -- valtype_cd
				null, -- tval_char
				null, -- nval_num
				null, -- valueflag_cd
				null, -- quantity_num
				null, -- units_cd
				case when fhir_data.effectiveDateTime is not null then fhir_data.effectiveDateTime
				     else '-infinity'::timestamptz end, -- end_date
				'', -- location_cd
				FHIR_id, -- observation_blob
				0, -- confidence_num
				now(), -- update_date
				now(), -- download_date
				now(), -- import_date
				FHIR_sourcesystem, -- sourcesystem_cd
				1, -- upload_id
				nextval('instance_num_seq'), -- text_search_index
				medication_reference -- fhir_reference
		  from (
		      with FhirTempTable(fhir2) AS (select fhir)
				select 
					--jsonb_path_query(fhir2, '$.id')->>0 as ID,
					(fhir2->>'id')::text as ID,
					effectiveDateTime,
					fhir_medication.code as medication_code,
		            fhir_medication.system as medication_system,
		            FhirTempTable.fhir2->'medicationReference'->>'reference' as medication_reference,
		            medicationCodeableConcept_coding_code,
		            medicationCodeableConcept_coding_system
				from FhirTempTable
				left join i2b2miracum.fhir_medication
		  	           on FhirTempTable.fhir2->'medicationReference'->>'reference' = 'Medication/' || fhir_medication.id
				left join (select (fhir2->>'effectiveDateTime')::timestamp as effectiveDateTime
							 from FhirTempTable) as sq1 on true
				left join (select jsonb_array_elements(fhir2->'medicationCodeableConcept'->'coding')->>'code' as medicationCodeableConcept_coding_code,
		  						  jsonb_array_elements(fhir2->'medicationCodeableConcept'->'coding')->>'system' as medicationCodeableConcept_coding_system
							 from FhirTempTable) as sq2 on true
		      ) fhir_data;		  
			/*from (select (new_as_table.fhir->>'effectiveDateTime')::timestamp as effectiveDateTime,
		               fhir_medication.code as medication_code,
		               fhir_medication.system as medication_system,
		               new_as_table.fhir->'medicationReference'->>'reference' as medication_reference, -- from i2b2 table "fhir_medication"
		               jsonb_array_elements(new_as_table.fhir->'medicationCodeableConcept'->'coding')->>'code' as code, -- from GECCO resource
  		               jsonb_array_elements(new_as_table.fhir->'medicationCodeableConcept'->'coding')->>'system' as system -- from GECCO resource
		  	      from (select fhir) new_as_table 
		  	           left join i2b2miracum.fhir_medication
		  	           on new_as_table.fhir->'medicationReference'->>'reference' = 'Medication/' || fhir_medication.id
		  	   ) fhir_data;*/
	end if;
	--
	--return null; -- Return nothing. This prevents that the FHIR data is actually written into the "FHIR" table.
exception 
	when others then
		perform i2b2miracum.fhir_elt_log('ERROR: Exception cought: ' || sqlerrm || ' FHIR = ' || fhir);
		insert into i2b2miracum.fhir_failed(ts, message, fhir) values (now(), sqlerrm, fhir);
		--return null;
end;
$$;

-- Connect trigger and function:
drop trigger if exists fhir_inserted on i2b2miracum.fhir;
create trigger fhir_inserted before insert on i2b2miracum.fhir for each row execute procedure i2b2miracum.fhir_inserted();

-- ============= Some Test Data =============

/*

INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Patient", "id": "Patient1", "meta": { "source": "Patient1.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/PatientIn" ] }, "identifier": [ { "use": "official", "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } ], "gender": "male", "birthDate": "1977-04-27", "deceasedDateTime": "2000-12-12T12:12:12+00:00", "address": [ { "type": "both", "city": "Entenhausen", "postalCode": "123456", "country": "DE" } ] }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Patient", "id": "Patient2", "meta": { "source": "Patient2.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/PatientIn" ] }, "identifier": [ { "use": "official", "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient2" } ], "gender": "female", "birthDate": "1978-04-27", "deceasedDateTime": "2001-12-12T12:12:12+00:00", "address": [ { "type": "both", "city": "Entenhausen", "postalCode": "123457", "country": "DE" } ] }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Patient", "id": "Patient1", "meta": { "source": "Patient3.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/PatientIn" ] }, "identifier": [ { "use": "official", "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient3" } ], "gender": "male", "birthDate": "1977-04-11", "address": [ { "type": "both", "city": "Entenhausen", "postalCode": "123456", "country": "DE" } ] }');

INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Encounter", "id": "Encounter1", "meta": { "source": "Encounter1.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Versorgungsfall" ] }, "identifier": [ { "use": "official", "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1", "assigner": { "identifier": { "system": "http://fhir.de/NamingSystem/arge-ik/iknr", "value": "260950567" } } } ], "status": "finished", "class": { "system": "https://www.medizininformatik-initiative.de/fhir/core/modul-fall/CodeSystem/Versorgungsfallklasse", "code": "stationaer", "display": "Stationär" }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } }, "period": { "start": "2020-01-01T06:00:00+00:00", "end": "2020-01-20T16:00:00+00:00" }, "diagnosis": [ { "condition": { "reference": "Condition/Condition1" }, "use": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/diagnosis-role", "code": "AD", "display": "Admission diagnosis" } ] } } ] }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Encounter", "id": "Encounter2", "meta": { "source": "Encounter2.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Versorgungsfall" ] }, "identifier": [ { "use": "official", "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter2", "assigner": { "identifier": { "system": "http://fhir.de/NamingSystem/arge-ik/iknr", "value": "260950567" } } } ], "status": "finished", "class": { "system": "https://www.medizininformatik-initiative.de/fhir/core/modul-fall/CodeSystem/Versorgungsfallklasse", "code": "stationaer", "display": "Stationär" }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient2" } }, "period": { "start": "2020-03-01T06:00:00+00:00", "end": "2020-03-20T16:00:00+00:00" }, "diagnosis": [ { "condition": { "reference": "Condition/Condition2" }, "use": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/diagnosis-role", "code": "AD", "display": "Admission diagnosis" } ] } } ] }');

INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition1", "meta": { "source": "Condition1.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K59.0" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "onsetDateTime": "2014-06-11T09:08:42+00:00", "recordedDate": "2014-06-11T09:03:42+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition2", "meta": { "source": "Condition2.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K60.0" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient2" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter2" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');

-- Test mit mehreren Codings:
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition3", "meta": { "source": "Condition3.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/System1", "version": "2015", "code": "Code1" }, { "system": "http://fhir.de/CodeSystem/dimdi/System2", "version": "2015", "code": "Code2" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "onsetDateTime": "2014-06-11T09:08:42+00:00", "recordedDate": "2014-06-11T09:03:42+00:00" }');

-- More data so that i2b2 (with obfuscation) shows a result:
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition4", "meta": { "source": "Condition4.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K76.9" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient4" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter4" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition5", "meta": { "source": "Condition5.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K76.9" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient5" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter5" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition6", "meta": { "source": "Condition6.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K76.9" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient6" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter6" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition7", "meta": { "source": "Condition7.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K76.9" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient7" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter7" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Condition", "id": "Condition8", "meta": { "source": "Condition8.json", "profile": [ "https://fhir.miracum.org/core/StructureDefinition/Diagnose" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateConditionId", "value": "36574576345432" } ], "verificationStatus": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/icd-10-gm", "version": "2015", "code": "K76.9" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient8" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter8" } }, "onsetDateTime": "2015-06-11T09:08:42+00:00", "recordedDate": "2016-06-11T09:03:42+00:00" }');

INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Observation", "id": "Observation1", "meta": { "source": "Labor1.json", "profile": [ "https://www.medizininformatik-initiative.de/fhir/core/modul-labor/StructureDefinition/ObservationLab" ] }, "identifier": [ { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "OBI" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/swisslab/labObservationId", "value": "123123123123-123123123123", "assigner": { "identifier": { "system": "https://www.medizininformatik-initiative.de/fhir/core/NamingSystem/org-identifier", "value": "UKER" } } } ], "status": "final", "category": [ { "coding": [ { "system": "http://loinc.org", "code": "26436-6" }, { "system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory" } ] } ], "code": { "coding": [ { "system": "http://loinc.org", "code": "41653-7" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } }, "encounter": { "reference": "Encounter/Encounter1", "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "effectiveDateTime": "2014-12-22T16:23:00+00:00", "issued": "2014-12-22T16:23:00+00:00", "valueQuantity": { "value": 134, "unit": "mg/dL", "system": "http://unitsofmeasure.org", "code": "mg/dL" } }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Observation", "id": "Observation2", "meta": { "source": "Labor2.json", "profile": [ "https://www.medizininformatik-initiative.de/fhir/core/modul-labor/StructureDefinition/ObservationLab" ] }, "identifier": [ { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "OBI" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/swisslab/labObservationId", "value": "5675675567856785678", "assigner": { "identifier": { "system": "https://www.medizininformatik-initiative.de/fhir/core/NamingSystem/org-identifier", "value": "UKER" } } } ], "status": "final", "category": [ { "coding": [ { "system": "http://loinc.org", "code": "26436-6" }, { "system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory" } ] } ], "code": { "coding": [ { "system": "http://loinc.org", "code": "41653-8" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient2" } }, "encounter": { "reference": "Encounter/Encounter2", "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter2" } }, "effectiveDateTime": "2014-12-23T16:23:00+00:00", "issued": "2014-12-23T16:23:00+00:00", "valueQuantity": { "value": 135, "unit": "mg/dL", "system": "http://unitsofmeasure.org", "code": "mg/dL" } }');

INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Procedure", "id": "Procedure1", "meta": { "source": "Procedure1.json", "profile": [ "https://www.medizininformatik-initiative.de/fhir/core/modul-prozedur/StructureDefinition/Procedure" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateProcedureId", "value": "123123123123" } ], "status": "completed", "category": { "coding": [ { "system": "http://snomed.info/sct", "code": "103693007", "display": "Diagnostic procedure" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/ops", "version": "2020", "code": "1-632.0" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient1" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "performedDateTime": "2020-07-15T06:42:00+00:00" }');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Procedure", "id": "Procedure2", "meta": { "source": "Procedure2.json", "profile": [ "https://www.medizininformatik-initiative.de/fhir/core/modul-prozedur/StructureDefinition/Procedure" ] }, "identifier": [ { "use": "official", "system": "https://fhir.diz.uk-erlangen/NamingSystem/kdbSurrogateProcedureId", "value": "3456345643563465" } ], "status": "completed", "category": { "coding": [ { "system": "http://snomed.info/sct", "code": "103693007", "display": "Diagnostic procedure" } ] }, "code": { "coding": [ { "system": "http://fhir.de/CodeSystem/dimdi/ops", "version": "2021", "code": "1-634.0" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId", "value": "Patient2" } }, "encounter": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "performedDateTime": "2021-07-15T06:42:00+00:00" }');

-- Test mit fehlenden Daten (Subject), muss neuen Patienten "UNKNOWN" anlegen:
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{ "resourceType": "Observation", "id": "Observation3", "meta": { "source": "Labor3.json", "profile": [ "https://www.medizininformatik-initiative.de/fhir/core/modul-labor/StructureDefinition/ObservationLab" ] }, "identifier": [ { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "OBI" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/swisslab/labObservationId", "value": "123123123123-123123123123", "assigner": { "identifier": { "system": "https://www.medizininformatik-initiative.de/fhir/core/NamingSystem/org-identifier", "value": "UKER" } } } ], "status": "final", "category": [ { "coding": [ { "system": "http://loinc.org", "code": "26436-6" }, { "system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "laboratory" } ] } ], "code": { "coding": [ { "system": "http://loinc.org", "code": "41653-7" } ] }, "subject": { "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId" } }, "encounter": { "reference": "Encounter/Encounter1", "identifier": { "type": { "coding": [ { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "VN" } ] }, "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId", "value": "Encounter1" } }, "effectiveDateTime": "2014-12-22T16:23:00+00:00", "issued": "2014-12-22T16:23:00+00:00", "valueQuantity": { "value": 134, "unit": "mg/dL", "system": "http://unitsofmeasure.org", "code": "mg/dL" } }');

-- Reihenfolge bei Medication muss egal sein:
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{"id": "Medication1", "code": {"coding": [{"code": "N06AX16", "system": "http://fhir.de/CodeSystem/dimdi/atc", "display": "Venlafaxin"}, {"code": "N06AX17", "system": "http://fhir.de/CodeSystem/dimdi/atc", "display": "Fake Venlafaxin"}]}, "meta": {"profile": ["https://www.medizininformatik-initiative.de/fhir/core/StructureDefinition/Medication"]}, "identifier": [{"value": "Venlafaxin_25.0mg", "system": "https://averbis.com/de.averbis.types.health.Medication"}], "ingredient": [{"itemCodeableConcept": {"coding": [{"system": "http://fhir.de/CodeSystem/dimdi/atc", "display": "Venlafaxin"}]}}], "resourceType": "Medication"}');
INSERT INTO i2b2miracum.fhir (fhir) VALUES ('{"id": "MedicationStatement1", "meta": {"profile": ["https://www.medizininformatik-initiative.de/fhir/core/StructureDefinition/MedicationStatement"], "security": [{"code": "PSEUDED", "system": "http://terminology.hl7.org/CodeSystem/v3-ObservationValue", "display": "part of the resource is pseudonymized"}]}, "dosage": [{"text": "Cisplatin (50 mg/m²", "doseAndRate": [{"doseQuantity": {"unit": "mg/m²", "value": 50.0}}]}], "status": "unknown", "context": {"type": "Encounter", "reference": "Encounter/XXXXXXXXXXXXX", "identifier": {"type": {"text": "Visit number", "coding": [{"code": "VN", "system": "http://terminology.hl7.org/CodeSystem/v2-0203"}]}, "value": "Encounter4", "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/encounterId"}}, "subject": {"type": "Patient", "reference": "Patient/XXXXXXXXXXXXXXX", "identifier": {"type": {"text": "Medical record number", "coding": [{"code": "MR", "system": "http://terminology.hl7.org/CodeSystem/v2-0203"}]}, "value": "Patient4", "system": "https://fhir.diz.uk-erlangen.de/NamingSystem/patientId"}}, "identifier": [{"value": "Cisplatin_50.0mg/m²_208004", "system": "https://averbis.com/de.averbis.types.health.Medication"}], "dateAsserted": "2008-07-29T17:44:00+00:00", "resourceType": "MedicationStatement", "effectiveDateTime": "2008-07-29T17:44:00+00:00", "medicationReference": {"type": "Medication", "reference": "Medication/Medication1", "identifier": {"value": "Cisplatin_50.0mg/m²", "system": "https://averbis.com/de.averbis.types.health.Medication"}}}');

*/
