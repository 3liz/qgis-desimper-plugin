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

-- communes communes_code_insee_key
ALTER TABLE ONLY desimper.communes
    ADD CONSTRAINT communes_code_insee_key UNIQUE (code_insee);


-- communes communes_pkey
ALTER TABLE ONLY desimper.communes
    ADD CONSTRAINT communes_pkey PRIMARY KEY (id);


-- contextes_projets contextes_projets_pkey
ALTER TABLE ONLY desimper.contextes_projets
    ADD CONSTRAINT contextes_projets_pkey PRIMARY KEY (id);


-- liste_contextes liste_contextes_code_key
ALTER TABLE ONLY desimper.liste_contextes
    ADD CONSTRAINT liste_contextes_code_key UNIQUE (code);


-- liste_contextes liste_contextes_libelle_key
ALTER TABLE ONLY desimper.liste_contextes
    ADD CONSTRAINT liste_contextes_libelle_key UNIQUE (libelle);


-- liste_contextes liste_contextes_pkey
ALTER TABLE ONLY desimper.liste_contextes
    ADD CONSTRAINT liste_contextes_pkey PRIMARY KEY (id);


-- liste_contextes liste_contextes_table_name_key
ALTER TABLE ONLY desimper.liste_contextes
    ADD CONSTRAINT liste_contextes_table_name_key UNIQUE (nom_table);


-- nomenclature_destinations nomenclature_destinations_code_key
ALTER TABLE ONLY desimper.nomenclature_destinations
    ADD CONSTRAINT nomenclature_destinations_code_key UNIQUE (code);


-- nomenclature_destinations nomenclature_destinations_libelle_key
ALTER TABLE ONLY desimper.nomenclature_destinations
    ADD CONSTRAINT nomenclature_destinations_libelle_key UNIQUE (libelle);


-- nomenclature_destinations nomenclature_destinations_pkey
ALTER TABLE ONLY desimper.nomenclature_destinations
    ADD CONSTRAINT nomenclature_destinations_pkey PRIMARY KEY (id);


-- nomenclature_pollution nomenclature_pollution_code_key
ALTER TABLE ONLY desimper.nomenclature_pollution
    ADD CONSTRAINT nomenclature_pollution_code_key UNIQUE (code);


-- nomenclature_pollution nomenclature_pollution_libelle_key
ALTER TABLE ONLY desimper.nomenclature_pollution
    ADD CONSTRAINT nomenclature_pollution_libelle_key UNIQUE (libelle);


-- nomenclature_pollution nomenclature_pollution_pkey
ALTER TABLE ONLY desimper.nomenclature_pollution
    ADD CONSTRAINT nomenclature_pollution_pkey PRIMARY KEY (id);


-- nomenclature_revetements nomenclature_revetements_code_key
ALTER TABLE ONLY desimper.nomenclature_revetements
    ADD CONSTRAINT nomenclature_revetements_code_key UNIQUE (code);


-- nomenclature_revetements nomenclature_revetements_libelle_key
ALTER TABLE ONLY desimper.nomenclature_revetements
    ADD CONSTRAINT nomenclature_revetements_libelle_key UNIQUE (libelle);


-- nomenclature_revetements nomenclature_revetements_pkey
ALTER TABLE ONLY desimper.nomenclature_revetements
    ADD CONSTRAINT nomenclature_revetements_pkey PRIMARY KEY (id);


-- nomenclature_type_projet nomenclature_type_projet_code_key
ALTER TABLE ONLY desimper.nomenclature_type_projet
    ADD CONSTRAINT nomenclature_type_projet_code_key UNIQUE (code);


-- nomenclature_type_projet nomenclature_type_projet_libelle_key
ALTER TABLE ONLY desimper.nomenclature_type_projet
    ADD CONSTRAINT nomenclature_type_projet_libelle_key UNIQUE (libelle);


-- nomenclature_type_projet nomenclature_type_projet_pkey
ALTER TABLE ONLY desimper.nomenclature_type_projet
    ADD CONSTRAINT nomenclature_type_projet_pkey PRIMARY KEY (id);


-- nomenclature_usages_surface nomenclature_usages_surface_code_key
ALTER TABLE ONLY desimper.nomenclature_usages_surface
    ADD CONSTRAINT nomenclature_usages_surface_code_key UNIQUE (code);


-- nomenclature_usages_surface nomenclature_usages_surface_libelle_key
ALTER TABLE ONLY desimper.nomenclature_usages_surface
    ADD CONSTRAINT nomenclature_usages_surface_libelle_key UNIQUE (libelle);


-- nomenclature_usages_surface nomenclature_usages_surface_pkey
ALTER TABLE ONLY desimper.nomenclature_usages_surface
    ADD CONSTRAINT nomenclature_usages_surface_pkey PRIMARY KEY (id);


-- pluviometrie pluviometrie_pkey
ALTER TABLE ONLY desimper.pluviometrie
    ADD CONSTRAINT pluviometrie_pkey PRIMARY KEY (id);


-- projets projets_libelle_key
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT projets_libelle_key UNIQUE (libelle);


-- projets projets_pkey
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT projets_pkey PRIMARY KEY (id);


-- surfaces_projet surfaces_projet_pkey
ALTER TABLE ONLY desimper.surfaces_projet
    ADD CONSTRAINT surfaces_projet_pkey PRIMARY KEY (id);


-- variantes variantes_libelle_key
ALTER TABLE ONLY desimper.variantes
    ADD CONSTRAINT variantes_libelle_key UNIQUE (libelle);


-- variantes variantes_pkey
ALTER TABLE ONLY desimper.variantes
    ADD CONSTRAINT variantes_pkey PRIMARY KEY (id);


-- projets fk_commune_principale
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT fk_commune_principale FOREIGN KEY (fk_commune_principale) REFERENCES desimper.communes(code_insee);


-- projets fk_destination
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT fk_destination FOREIGN KEY (fk_destination) REFERENCES desimper.nomenclature_destinations(code);


-- contextes_projets fk_id_projet
ALTER TABLE ONLY desimper.contextes_projets
    ADD CONSTRAINT fk_id_projet FOREIGN KEY (fk_id_projet) REFERENCES desimper.projets(id) ON DELETE CASCADE;


-- projets fk_pollution
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT fk_pollution FOREIGN KEY (fk_pollution) REFERENCES desimper.nomenclature_pollution(code);


-- surfaces_projet fk_projet_surface_revetements
ALTER TABLE ONLY desimper.surfaces_projet
    ADD CONSTRAINT fk_projet_surface_revetements FOREIGN KEY (fk_revetements) REFERENCES desimper.nomenclature_revetements(code);


-- surfaces_projet fk_projet_surface_usages_surface
ALTER TABLE ONLY desimper.surfaces_projet
    ADD CONSTRAINT fk_projet_surface_usages_surface FOREIGN KEY (fk_usages_surface) REFERENCES desimper.nomenclature_usages_surface(code);


-- surfaces_projet fk_projet_surfaces_projet
ALTER TABLE ONLY desimper.surfaces_projet
    ADD CONSTRAINT fk_projet_surfaces_projet FOREIGN KEY (fk_id_projet) REFERENCES desimper.projets(id);


-- variantes fk_projet_variantes
ALTER TABLE ONLY desimper.variantes
    ADD CONSTRAINT fk_projet_variantes FOREIGN KEY (fk_id_projet) REFERENCES desimper.projets(id);


-- projets fk_type_projet
ALTER TABLE ONLY desimper.projets
    ADD CONSTRAINT fk_type_projet FOREIGN KEY (fk_type_projet) REFERENCES desimper.nomenclature_type_projet(code);


-- surfaces_projet fk_variante_surfaces_projet
ALTER TABLE ONLY desimper.surfaces_projet
    ADD CONSTRAINT fk_variante_surfaces_projet FOREIGN KEY (fk_id_variante) REFERENCES desimper.variantes(id);


--
-- PostgreSQL database dump complete
--



