-- ==================
-- Postprocessing.sql
-- ==================
-- Date: 2021-02-01

-- Author: Sebastian Mate (Erlangen)
     
-- Remove certain entries from the i2b2 ontology that were derived from the GECCO Art-Decor:                     

delete from i2b2miracum.i2b2 where c_name = 'Certainty of Absence';
delete from i2b2miracum.i2b2 where c_name = 'Certainty of Presence';
delete from i2b2miracum.i2b2 where c_name = 'Data Absent Reason Expansion';
delete from i2b2miracum.i2b2 where c_name = 'Uncertainty of Presence';
delete from i2b2miracum.i2b2 where c_name = 'Tumor Disease Status';
delete from i2b2miracum.i2b2 where c_name = 'Event Status Expansion';
delete from i2b2miracum.i2b2 where c_name = 'Resuscitation Status';
delete from i2b2miracum.i2b2 where c_name = 'Yes No Unknown Other';
delete from i2b2miracum.i2b2 where c_name = 'Detected Not Detected Inconclusive';
delete from i2b2miracum.i2b2 where c_name = 'Event Status Expansion';

-- Remove old modifier entries from i2b2 ontology:

delete from i2b2miracum.i2b2 where c_visualattributes = 'RA ';

-- select * from i2b2miracum.i2b2 where c_comment != '';

-- Find other modifier codes that are not yet in the ontology:

--select distinct modifier_cd from i2b2miracum.observation_fact
--where modifier_cd not in (select modifier_cd from i2b2miracum.modifier_dimension)
--and modifier_cd not in ('@', 'SNOMED-CT:3457005', 'SNOMED-CT:840546002', 'LOINC:LA18980-5', 'SNOMED-CT:304253006');

WITH modifiers(type, label, modifier) AS ( VALUES ('Condition', 'Condition Verification Status = Confirmed', 'CVS:confirmed'),
 												  ('Condition', 'Condition Verification Status = Refuted', 'CVS:refuted'),
 												  ('Condition', 'SNOMED-CT = Definitely Not Present', 'SNOMED-CT:410594000'),
 												  ('Condition', 'SNOMED-CT = Confirmed present', 'SNOMED-CT:410605003'),
 												  ('Condition', 'SNOMED-CT = Unknown', 'SNOMED-CT:261665006'),
 												  --('Observation', 'Patient referral', 'SNOMED-CT:3457005'), -- nicht allg. gültig
 												  --('Observation', 'Exposure to SARS-CoV-2', 'SNOMED-CT:840546002'), -- nicht allg. gültig
 												  ('Observation', 'SNOMED-CT = Yes', 'SNOMED-CT:373066001'),
 												  ('Observation', 'SNOMED-CT = No', 'SNOMED-CT:373067005'),
 												  ('Observation', 'SNOMED-CT = Detected', 'SNOMED-CT:260373001'),
 												  ('Observation', 'SNOMED-CT = Not Detected', 'SNOMED-CT:260415000'),
 												  ('Procedure', 'SNOMED-CT = Lung Structure', 'SNOMED-CT:39607008')
 												  --('Observation', 'SNOMED-CT = Not For Resuscitation', 'SNOMED-CT:304253006') -- nicht allg. gültig
								         )
insert into i2b2miracum.i2b2 (c_hlevel, c_fullname, c_name, c_synonym_cd, c_visualattributes, c_totalnum, c_basecode, c_metadataxml, c_facttablecolumn, c_tablename, c_columnname, c_columndatatype, c_operator, c_dimcode, c_comment, c_tooltip, m_applied_path, update_date, download_date, import_date, sourcesystem_cd, valuetype_cd, m_exclusion_cd, c_path, c_symbol)
select 1 c_hlevel,
	   '\' || modifiers.label || '\' c_fullname, -- Modifier entry
	   modifiers.label c_name, -- Modifier entry
	   'N' c_synonym_cd,
	   'RA ' c_visualattributes,
	   null c_totalnum,
	   modifiers.modifier c_basecode,
	   null c_metadataxml,
	   'modifier_cd' c_facttablecolumn,
	   'modifier_dimension' c_tablename,
	   'modifier_path' c_columnname,
	   'T' c_columndatatype,
	   'LIKE' c_operator,
	   '\' || modifiers.label || '\' c_dimcode,
	   null c_comment,
	   modifiers.modifier c_tooltip,
	   c_fullname || '%' m_applied_path,
	   now() update_date,
	   now() download_date,
	   now() import_date,
	   'Postprocessing.sql' sourcesystem_cd,
	   null valuetype_cd,
	   null m_exclusion_cd,
	   null c_path,
	   null c_symbol
  from i2b2miracum.i2b2, modifiers
 where i2b2.c_comment like '%' ||modifiers.type
order by i2b2.c_comment;

-- Rebuild MODIFIER_DIMENSION:

delete from i2b2miracum.modifier_dimension;
insert into	i2b2miracum.modifier_dimension (modifier_path, modifier_cd, name_char, modifier_blob, update_date, download_date, import_date, sourcesystem_cd, upload_id)
select distinct
	c_fullname, -- modifier_path
	c_basecode, -- modifier_cd
	c_name, -- name_char
	null, -- modifier_blob
	now(), -- update_date
	now(), -- download_date
	now(), -- import_date
	'Postprocessing.sql', -- sourcesystem_cd      
	1 -- upload_id
from i2b2miracum.i2b2
 where c_visualattributes = 'RA ';

-- Rebuild CONCEPT_DIMENSION:

delete from i2b2miracum.concept_dimension;
insert into i2b2miracum.concept_dimension (concept_cd, concept_path, name_char, concept_blob, sourcesystem_cd) select distinct c_basecode, c_fullname, c_name, null, null from i2b2miracum.i2b2 where c_visualattributes like 'LA%';
commit;
           