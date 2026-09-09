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

-- FUNCTION aa_before_insert_or_update()
COMMENT ON FUNCTION desimper.aa_before_insert_or_update() IS 'Met automatiquement à jour les champs suivants : cree_le, modifie_le, geom, commune_principale, surface_m';


-- FUNCTION fill_contextes_projets(id_projet integer)
COMMENT ON FUNCTION desimper.fill_contextes_projets(id_projet integer) IS 'Ajoute à la table contextes_projets les contextes qui intersectent le projet';


-- FUNCTION import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text)
COMMENT ON FUNCTION desimper.import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text) IS 'Import data from temporary tables into schema and table defined in desimper.liste_contextes';


-- FUNCTION is_given_type(s text, t text)
COMMENT ON FUNCTION desimper.is_given_type(s text, t text) IS ' Teste si la valeur d''un champ correspond au type donné. 
Retourne vrai s''il est possible de caster la valeur dans le type donné attendu.
Valeurs vides et NULL sont toujours considérées valides. 
Si le type n''est pas supporté, la valeur est considérée invalide.';


-- FUNCTION trg_after_projet_insert_or_update()
COMMENT ON FUNCTION desimper.trg_after_projet_insert_or_update() IS 'Fonction trigger permettant de mettre à jour les tables de données métier en lien avec le projet.
Appelle desimper.fill_contextes_projets() avec l''identifiant du projet.
Ne fait rien si la géométrie du projet n''a pas changé.';


-- communes
COMMENT ON TABLE desimper.communes IS 'Table des communes';


-- communes.id
COMMENT ON COLUMN desimper.communes.id IS 'Identifiant unique des communes';


-- communes.code_insee
COMMENT ON COLUMN desimper.communes.code_insee IS 'Code INSEE de la commune';


-- communes.libelle
COMMENT ON COLUMN desimper.communes.libelle IS 'Libelle de la commune';


-- communes.geom
COMMENT ON COLUMN desimper.communes.geom IS 'Polygone représentant la commune';


-- contextes_projets
COMMENT ON TABLE desimper.contextes_projets IS 'Table des contextes associés aux projets';


-- contextes_projets.id
COMMENT ON COLUMN desimper.contextes_projets.id IS 'Identifiant unique des contextes associés aux projets';


-- contextes_projets.fk_id_projet
COMMENT ON COLUMN desimper.contextes_projets.fk_id_projet IS 'Identifiant du projet';


-- contextes_projets.geom
COMMENT ON COLUMN desimper.contextes_projets.geom IS 'Polygone représentant le contexte au sein du projet';


-- contextes_projets.surface_m
COMMENT ON COLUMN desimper.contextes_projets.surface_m IS 'Surface en m² du contexte';


-- contextes_projets.login
COMMENT ON COLUMN desimper.contextes_projets.login IS 'Login de l''utilisateur qui a créé le contexte';


-- liste_contextes
COMMENT ON TABLE desimper.liste_contextes IS 'Table listant l''ensemble des contextes et leurs caractéristiques';


-- liste_contextes.id
COMMENT ON COLUMN desimper.liste_contextes.id IS 'Identifiant unique des contextes';


-- liste_contextes.code
COMMENT ON COLUMN desimper.liste_contextes.code IS 'Code du contexte';


-- liste_contextes.libelle
COMMENT ON COLUMN desimper.liste_contextes.libelle IS 'Libelle du contexte';


-- liste_contextes.description
COMMENT ON COLUMN desimper.liste_contextes.description IS 'Description du contexte';


-- liste_contextes.type_valeur
COMMENT ON COLUMN desimper.liste_contextes.type_valeur IS 'Type des valeurs qualifiant le contexte (integer, text...)';


-- liste_contextes.login
COMMENT ON COLUMN desimper.liste_contextes.login IS 'Login de l''utilisateur qui a créé le contexte';


-- liste_contextes.cree_le
COMMENT ON COLUMN desimper.liste_contextes.cree_le IS 'Date de création du contexte';


-- liste_contextes.modifie_le
COMMENT ON COLUMN desimper.liste_contextes.modifie_le IS 'Date de la dernière modification du contexte';


-- metadata
COMMENT ON TABLE desimper.metadata IS 'DO NOT DROP THIS TABLE ! Metadata of the structure (version and date). Usefull for database structure and glossary data migrations between versions';


-- nomenclature_destinations
COMMENT ON TABLE desimper.nomenclature_destinations IS 'Table des destinations';


-- nomenclature_destinations.id
COMMENT ON COLUMN desimper.nomenclature_destinations.id IS 'Identifiant unique des destinations';


-- nomenclature_destinations.code
COMMENT ON COLUMN desimper.nomenclature_destinations.code IS 'Code de la destination';


-- nomenclature_destinations.libelle
COMMENT ON COLUMN desimper.nomenclature_destinations.libelle IS 'Libellé de la destination';


-- nomenclature_pollution
COMMENT ON TABLE desimper.nomenclature_pollution IS 'Table des pollutions';


-- nomenclature_pollution.id
COMMENT ON COLUMN desimper.nomenclature_pollution.id IS 'Identifiant unique des pollutions';


-- nomenclature_pollution.code
COMMENT ON COLUMN desimper.nomenclature_pollution.code IS 'Code de la pollution';


-- nomenclature_pollution.libelle
COMMENT ON COLUMN desimper.nomenclature_pollution.libelle IS 'Libellé du type de pollution';


-- nomenclature_revetements
COMMENT ON TABLE desimper.nomenclature_revetements IS 'Table des revêtements';


-- nomenclature_revetements.id
COMMENT ON COLUMN desimper.nomenclature_revetements.id IS 'Identifiant unique du revêtement';


-- nomenclature_revetements.code
COMMENT ON COLUMN desimper.nomenclature_revetements.code IS 'Code du revêtement';


-- nomenclature_revetements.libelle
COMMENT ON COLUMN desimper.nomenclature_revetements.libelle IS 'Libellé du revêtement';


-- nomenclature_revetements.impermeable
COMMENT ON COLUMN desimper.nomenclature_revetements.impermeable IS 'Indique si le revêtement est imperméable (vrai) ou perméable (faux)';


-- nomenclature_type_projet
COMMENT ON TABLE desimper.nomenclature_type_projet IS 'Table des types de projets';


-- nomenclature_type_projet.id
COMMENT ON COLUMN desimper.nomenclature_type_projet.id IS 'Identifiant unique des types de projets';


-- nomenclature_type_projet.code
COMMENT ON COLUMN desimper.nomenclature_type_projet.code IS 'Code du type de projet';


-- nomenclature_type_projet.libelle
COMMENT ON COLUMN desimper.nomenclature_type_projet.libelle IS 'Libellé du type de projet';


-- nomenclature_usages_surface
COMMENT ON TABLE desimper.nomenclature_usages_surface IS 'Table des usages de surface';


-- nomenclature_usages_surface.id
COMMENT ON COLUMN desimper.nomenclature_usages_surface.id IS 'Identifiant unique des usages de surface';


-- nomenclature_usages_surface.code
COMMENT ON COLUMN desimper.nomenclature_usages_surface.code IS 'Code de l''usage de la surface';


-- nomenclature_usages_surface.libelle
COMMENT ON COLUMN desimper.nomenclature_usages_surface.libelle IS 'libelle de l''usage de la surface';


-- pluviometrie
COMMENT ON TABLE desimper.pluviometrie IS 'Table des pluviometries';


-- pluviometrie.id
COMMENT ON COLUMN desimper.pluviometrie.id IS 'Identifiant unique des pluviometries';


-- pluviometrie.geom
COMMENT ON COLUMN desimper.pluviometrie.geom IS 'Zone référentielle de pluviométrie';


-- pluviometrie.periode_retour_pluie
COMMENT ON COLUMN desimper.pluviometrie.periode_retour_pluie IS 'Periode de retour de la pluie';


-- pluviometrie.duree
COMMENT ON COLUMN desimper.pluviometrie.duree IS 'Durée de pluie';


-- pluviometrie.hauteur_precipitation
COMMENT ON COLUMN desimper.pluviometrie.hauteur_precipitation IS 'Hauteur des précipitations';


-- projets
COMMENT ON TABLE desimper.projets IS 'Table des projets';


-- projets.id
COMMENT ON COLUMN desimper.projets.id IS 'Identifiant unique des projets';


-- projets.libelle
COMMENT ON COLUMN desimper.projets.libelle IS 'Libellé du projet de désimpermeabilisation';


-- projets.fk_type_projet
COMMENT ON COLUMN desimper.projets.fk_type_projet IS 'Type de projet (Création, Requalification)';


-- projets.fk_destination
COMMENT ON COLUMN desimper.projets.fk_destination IS 'Destination du projet (Place, Parking...)';


-- projets.fk_pollution
COMMENT ON COLUMN desimper.projets.fk_pollution IS 'Usage susceptible de générer des pollutions (Non, Pollution chronique, Autre type de pollution)';


-- projets.fk_commune_principale
COMMENT ON COLUMN desimper.projets.fk_commune_principale IS 'Commune principale sur laquelle se trouve le projet, déterminée automatiquement. NULL si indéterminée';


-- projets.geom
COMMENT ON COLUMN desimper.projets.geom IS 'Polygone délimitant le projet';


-- projets.cree_le
COMMENT ON COLUMN desimper.projets.cree_le IS 'Date de création du projet';


-- projets.modifie_le
COMMENT ON COLUMN desimper.projets.modifie_le IS 'Date de modification du projet';


-- projets.login
COMMENT ON COLUMN desimper.projets.login IS 'Login de l''utilisateur qui a créé le contexte';


-- surfaces_projet
COMMENT ON TABLE desimper.surfaces_projet IS 'Table des surfaces du projet';


-- surfaces_projet.id
COMMENT ON COLUMN desimper.surfaces_projet.id IS 'Identifiant unique des surfaces';


-- surfaces_projet.fk_id_projet
COMMENT ON COLUMN desimper.surfaces_projet.fk_id_projet IS 'Identifiant du projet parent';


-- surfaces_projet.fk_id_variante
COMMENT ON COLUMN desimper.surfaces_projet.fk_id_variante IS 'Identifiant de la variante du projet';


-- surfaces_projet.geom
COMMENT ON COLUMN desimper.surfaces_projet.geom IS 'Polygone représentant la surface';


-- surfaces_projet.fk_usages_surface
COMMENT ON COLUMN desimper.surfaces_projet.fk_usages_surface IS 'Usage de la surface (Trottoir, Piste cyclable...)';


-- surfaces_projet.fk_revetements
COMMENT ON COLUMN desimper.surfaces_projet.fk_revetements IS 'Revêtement de la surface';


-- surfaces_projet.cree_le
COMMENT ON COLUMN desimper.surfaces_projet.cree_le IS 'Date de création de la surface';


-- surfaces_projet.modifie_le
COMMENT ON COLUMN desimper.surfaces_projet.modifie_le IS 'Date de modification de la surface';


-- surfaces_projet.login
COMMENT ON COLUMN desimper.surfaces_projet.login IS 'Login de l''utilisateur qui a créé le contexte';


-- variantes
COMMENT ON TABLE desimper.variantes IS 'Table des variantes. Une variante correspond à une "version" d''un projet';


-- variantes.id
COMMENT ON COLUMN desimper.variantes.id IS 'Identifiant unique des variantes';


-- variantes.fk_id_projet
COMMENT ON COLUMN desimper.variantes.fk_id_projet IS 'Identifiant du projet parent';


-- variantes.libelle
COMMENT ON COLUMN desimper.variantes.libelle IS 'Libellé de la variante';


-- variantes.etat_initial
COMMENT ON COLUMN desimper.variantes.etat_initial IS 'État initial de la variante. "Vrai" pour la première variante qui établit une description réelle du projet.';


-- variantes.cree_le
COMMENT ON COLUMN desimper.variantes.cree_le IS 'Date de création de la variante';


-- variantes.modifie_le
COMMENT ON COLUMN desimper.variantes.modifie_le IS 'Date de modification de la variante';


-- variantes.login
COMMENT ON COLUMN desimper.variantes.login IS 'Login de l''utilisateur qui a créé le contexte';


--
-- PostgreSQL database dump complete
--



