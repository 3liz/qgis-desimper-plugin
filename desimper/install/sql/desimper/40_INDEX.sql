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

-- bassins_versants_geom_idx
CREATE INDEX bassins_versants_geom_idx ON desimper.bassins_versants USING gist (geom);


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


-- fleches_ecoulement_fk_id_projet_idx
CREATE INDEX fleches_ecoulement_fk_id_projet_idx ON desimper.fleches_ecoulement USING btree (fk_id_projet);


-- fleches_ecoulement_geom_idx
CREATE INDEX fleches_ecoulement_geom_idx ON desimper.fleches_ecoulement USING gist (geom);


-- hydro_bv_amont_geom_idx
CREATE INDEX hydro_bv_amont_geom_idx ON desimper.hydro_bv_amont USING gist (geom);


-- hydro_d8_raster_st_convexhull_idx
CREATE INDEX hydro_d8_raster_st_convexhull_idx ON desimper.hydro_d8_raster USING gist (public.st_convexhull(rast));


-- hydro_noeuds_ds_idx
CREATE INDEX hydro_noeuds_ds_idx ON desimper.hydro_noeuds USING btree (ds);


-- hydro_noeuds_geom_idx
CREATE INDEX hydro_noeuds_geom_idx ON desimper.hydro_noeuds USING gist (geom);


-- hydro_troncons_geom_idx
CREATE INDEX hydro_troncons_geom_idx ON desimper.hydro_troncons USING gist (geom);


-- hydro_troncons_id_idx
CREATE INDEX hydro_troncons_id_idx ON desimper.hydro_troncons USING btree (id);


-- lignes_ecoulement_fk_id_projet_idx
CREATE INDEX lignes_ecoulement_fk_id_projet_idx ON desimper.lignes_ecoulement USING btree (fk_id_projet);


-- lignes_ecoulement_geom_idx
CREATE INDEX lignes_ecoulement_geom_idx ON desimper.lignes_ecoulement USING gist (geom);


-- projets_geom_idx
CREATE INDEX projets_geom_idx ON desimper.projets USING gist (geom);


-- surfaces_projet_geom_idx
CREATE INDEX surfaces_projet_geom_idx ON desimper.surfaces_projet USING gist (geom);


-- variantes_fk_id_projet_etat_initial_idx
CREATE UNIQUE INDEX variantes_fk_id_projet_etat_initial_idx ON desimper.variantes USING btree (fk_id_projet) WHERE etat_initial;


--
-- PostgreSQL database dump complete
--



