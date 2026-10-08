--
-- PostgreSQL database dump
--






SET statement_timeout = 0;
SET lock_timeout = 0;


SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

-- communes_geom_idx
CREATE INDEX communes_geom_idx ON desimper.communes USING gist (geom);


-- contextes_projets_geom_idx
CREATE INDEX contextes_projets_geom_idx ON desimper.contextes_projets USING gist (geom);


-- fk_commune_principale_idx
CREATE INDEX fk_commune_principale_idx ON desimper.projets USING btree (fk_commune_principale);


-- fk_contextes_projets_id_projet_idx
CREATE INDEX fk_contextes_projets_id_projet_idx ON desimper.contextes_projets USING btree (fk_id_projet);


-- fk_destination_idx
CREATE INDEX fk_destination_idx ON desimper.projets USING btree (fk_destination);


-- fk_id_projet_surfaces_idx
CREATE INDEX fk_id_projet_surfaces_idx ON desimper.surfaces_projet USING btree (fk_id_projet);


-- fk_id_projet_variantes_idx
CREATE INDEX fk_id_projet_variantes_idx ON desimper.variantes USING btree (fk_id_projet);


-- fk_id_variante_idx
CREATE INDEX fk_id_variante_idx ON desimper.surfaces_projet USING btree (fk_id_variante);


-- fk_pollution_idx
CREATE INDEX fk_pollution_idx ON desimper.projets USING btree (fk_pollution);


-- fk_revetements_idx
CREATE INDEX fk_revetements_idx ON desimper.surfaces_projet USING btree (fk_revetements);


-- fk_type_projet_idx
CREATE INDEX fk_type_projet_idx ON desimper.projets USING btree (fk_type_projet);


-- fk_usages_surface_idx
CREATE INDEX fk_usages_surface_idx ON desimper.surfaces_projet USING btree (fk_usages_surface);


-- projets_geom_idx
CREATE INDEX projets_geom_idx ON desimper.projets USING gist (geom);


-- surfaces_projet_geom_idx
CREATE INDEX surfaces_projet_geom_idx ON desimper.surfaces_projet USING gist (geom);


--
-- PostgreSQL database dump complete
--



