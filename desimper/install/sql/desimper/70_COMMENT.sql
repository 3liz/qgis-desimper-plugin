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


-- FUNCTION calculer_bassin_versant(id_projet integer)
COMMENT ON FUNCTION desimper.calculer_bassin_versant(id_projet integer) IS 'Calcule (ou recalcule) le bassin versant automatique d''un projet avec desimper.hydro_bassin_polygone() et l''enregistre dans bassins_versants avec corrige = false.
Le bassin versant corrigé par l''utilisateur n''est pas modifié.
Renvoie le bassin versant en GeoJSON (FeatureCollection).';


-- FUNCTION calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision)
COMMENT ON FUNCTION desimper.calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision) IS 'Calcule (ou recalcule) les flèches et les lignes d''écoulement d''un projet avec desimper.hydro_fleches_ecoulement() et desimper.hydro_lignes_ecoulement(), et les enregistre dans fleches_ecoulement et lignes_ecoulement.
Paramètres : taille des mailles des flèches (m), espacement des départs des lignes (m), prolongement des lignes au-delà du projet (m).
Renvoie le nombre de flèches et de lignes enregistrées.';


-- FUNCTION creer_bassin_versant_corrige(id_projet integer)
COMMENT ON FUNCTION desimper.creer_bassin_versant_corrige(id_projet integer) IS 'Crée le bassin versant corrigé (corrige = true) d''un projet en copiant son bassin versant automatique.
Ne fait rien s''il existe déjà.
Renvoie l''identifiant du bassin versant corrigé.';


-- FUNCTION fill_contextes_projets(id_projet integer)
COMMENT ON FUNCTION desimper.fill_contextes_projets(id_projet integer) IS 'Ajoute à la table contextes_projets les contextes qui intersectent le projet';


-- FUNCTION hydro_bassin_point(p_point geometry, p_rayon double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_point(p_point geometry, p_rayon double precision) IS 'Bassin versant d''un point, recalé sur le réseau dans le rayon p_rayon (m) : remontée fine cellule par cellule dans son bassin élémentaire, unie aux bassins amont reconstruits.';


-- FUNCTION hydro_bassin_polygone(p_poly geometry, p_simplifier double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_polygone(p_poly geometry, p_simplifier double precision) IS 'Bassin contributif d''un polygone de projet, polygone inclus : une remontée par bassin élémentaire, depuis tous les exutoires du polygone. Simplifié avec la tolérance p_simplifier (m).';


-- FUNCTION hydro_bassin_versant(p_points geometry, p_rayon double precision, p_simplifier double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_versant(p_points geometry, p_rayon double precision, p_simplifier double precision) IS 'Bassin versant unique d''un point ou d''un multipoint, simplifié avec la tolérance p_simplifier (m).';


-- FUNCTION hydro_bassins_par_point(p_points geometry, p_rayon double precision)
COMMENT ON FUNCTION desimper.hydro_bassins_par_point(p_points geometry, p_rayon double precision) IS 'Un bassin versant par point d''un multipoint.';


-- FUNCTION hydro_elements_amont(p_departs bigint[], p_ouvrir boolean)
COMMENT ON FUNCTION desimper.hydro_elements_amont(p_departs bigint[], p_ouvrir boolean) IS 'Morceaux du bassin amont d''un ensemble de nœuds : polygone élémentaire des nœuds non précalculés, bassin amont stocké des nœuds précalculés (où la remontée s''arrête). p_ouvrir = true développe toujours les nœuds de départ.';


-- FUNCTION hydro_fleches_ecoulement(p_poly geometry, p_pas double precision)
COMMENT ON FUNCTION desimper.hydro_fleches_ecoulement(p_poly geometry, p_pas double precision) IS 'Flèches d''écoulement d''un polygone : direction moyenne de l''écoulement D8 (angle en degrés depuis le nord, sens horaire) et cohérence des directions, par maille de p_pas mètres.';


-- FUNCTION hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision, p_marge double precision)
COMMENT ON FUNCTION desimper.hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision, p_marge double precision) IS 'Lignes d''écoulement tracées de cellule en cellule depuis des départs espacés de p_espacement mètres dans le polygone, jusqu''à la sortie du polygone élargi de p_marge mètres.';


-- FUNCTION hydro_pixels(r raster)
COMMENT ON FUNCTION desimper.hydro_pixels(r raster) IS 'Pixels d''une tuile (ou d''un extrait de tuile) du raster D8, avec leur identifiant global de cellule (lig * ncols + col), leur ligne, leur colonne et leur valeur.';


-- FUNCTION hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean)
COMMENT ON FUNCTION desimper.hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean) IS 'Remontée multi-départs dans une zone (un nœud, ou une fenêtre hors nœud), unie aux bassins amont des nœuds qui s''y jettent.';


-- FUNCTION import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text)
COMMENT ON FUNCTION desimper.import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text) IS 'Import data from temporary tables into schema and table defined in desimper.liste_contextes';


-- FUNCTION is_given_type(s text, t text)
COMMENT ON FUNCTION desimper.is_given_type(s text, t text) IS ' Teste si la valeur d''un champ correspond au type donné. 
Retourne vrai s''il est possible de caster la valeur dans le type donné attendu.
Valeurs vides et NULL sont toujours considérées valides. 
Si le type n''est pas supporté, la valeur est considérée invalide.';


-- FUNCTION set_variantes_etat_initial()
COMMENT ON FUNCTION desimper.set_variantes_etat_initial() IS 'Fonction trigger calculant le champ etat_initial des variantes : vrai si le projet n''a pas encore de variante représentant son état initial, faux sinon.
La valeur envoyée par le client est ignorée. Elle n''est plus modifiée après la création, sauf si la variante change de projet.';


-- FUNCTION trg_after_projet_insert_or_update()
COMMENT ON FUNCTION desimper.trg_after_projet_insert_or_update() IS 'Fonction trigger permettant de mettre à jour les tables de données métier en lien avec le projet.
Appelle desimper.fill_contextes_projets() avec l''identifiant du projet.
Supprime le bassin versant automatique du projet (le bassin versant corrigé est conservé), ainsi que ses flèches et lignes d''écoulement.
Ne fait rien si la géométrie du projet n''a pas changé.';


-- bassins_versants
COMMENT ON TABLE desimper.bassins_versants IS 'Table pour stocker les bassins versants associés aux projets. Au plus 2 bassins versants par projet : celui calculé automatiquement (corrige = false) et celui corrigé par l''utilisateur (corrige = true).';


-- bassins_versants.id
COMMENT ON COLUMN desimper.bassins_versants.id IS 'Identifiant unique du bassin versant.';


-- bassins_versants.fk_id_projet
COMMENT ON COLUMN desimper.bassins_versants.fk_id_projet IS 'Projet associé au bassin versant.';


-- bassins_versants.corrige
COMMENT ON COLUMN desimper.bassins_versants.corrige IS 'Indique si le bassin versant a été corrigé par l''utilisateur.';


-- bassins_versants.geom
COMMENT ON COLUMN desimper.bassins_versants.geom IS 'Géométrie du bassin versant.';


-- bassins_versants.cree_le
COMMENT ON COLUMN desimper.bassins_versants.cree_le IS 'Date de création du bassin versant.';


-- bassins_versants.modifie_le
COMMENT ON COLUMN desimper.bassins_versants.modifie_le IS 'Date de dernière modification du bassin versant.';


-- bassins_versants.login
COMMENT ON COLUMN desimper.bassins_versants.login IS 'Login de l''utilisateur ayant modifié le bassin versant.';


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


-- contextes_projets.indicateur
COMMENT ON COLUMN desimper.contextes_projets.indicateur IS 'Indicateur en fonction de la valeur du contexte';


-- contextes_projets.est_contrainte
COMMENT ON COLUMN desimper.contextes_projets.est_contrainte IS 'Indique si le contexte est une contrainte';


-- contextes_projets.couleur
COMMENT ON COLUMN desimper.contextes_projets.couleur IS 'Couleur de représentation du contexte';


-- fleches_ecoulement
COMMENT ON TABLE desimper.fleches_ecoulement IS 'Flèches d''écoulement des projets : une flèche par maille, orientée selon la direction moyenne de l''écoulement D8 des cellules de la maille. Calculées avec desimper.hydro_fleches_ecoulement().';


-- fleches_ecoulement.id
COMMENT ON COLUMN desimper.fleches_ecoulement.id IS 'Identifiant unique de la flèche.';


-- fleches_ecoulement.fk_id_projet
COMMENT ON COLUMN desimper.fleches_ecoulement.fk_id_projet IS 'Projet associé à la flèche.';


-- fleches_ecoulement.angle
COMMENT ON COLUMN desimper.fleches_ecoulement.angle IS 'Direction de l''écoulement, en degrés depuis le nord dans le sens des aiguilles d''une montre (rotation des symboles QGIS).';


-- fleches_ecoulement.coherence
COMMENT ON COLUMN desimper.fleches_ecoulement.coherence IS 'Cohérence des directions de la maille, de 0 (replat, crête) à 1 (toutes les cellules vont dans le même sens).';


-- fleches_ecoulement.nb_cellules
COMMENT ON COLUMN desimper.fleches_ecoulement.nb_cellules IS 'Nombre de cellules du MNT prises en compte dans la maille.';


-- fleches_ecoulement.geom
COMMENT ON COLUMN desimper.fleches_ecoulement.geom IS 'Centre de la maille.';


-- fleches_ecoulement.cree_le
COMMENT ON COLUMN desimper.fleches_ecoulement.cree_le IS 'Date de calcul de la flèche.';


-- hydro_bv_amont
COMMENT ON TABLE desimper.hydro_bv_amont IS 'Bassins amont précalculés des nœuds qui drainent une grande surface (hydro_noeuds.precalc).';


-- hydro_bv_amont.id
COMMENT ON COLUMN desimper.hydro_bv_amont.id IS 'Nœud dont c''est le bassin amont.';


-- hydro_bv_amont.geom
COMMENT ON COLUMN desimper.hydro_bv_amont.geom IS 'Bassin amont complet du nœud.';


-- hydro_codes_d8
COMMENT ON TABLE desimper.hydro_codes_d8 IS 'Codage des directions D8 de TauDEM : 1 = est, puis sens antihoraire jusqu''à 8 = sud-est.';


-- hydro_codes_d8.code
COMMENT ON COLUMN desimper.hydro_codes_d8.code IS 'Code de direction D8 de TauDEM.';


-- hydro_codes_d8.dl
COMMENT ON COLUMN desimper.hydro_codes_d8.dl IS 'Décalage en ligne vers la cellule aval (positif vers le bas).';


-- hydro_codes_d8.dc
COMMENT ON COLUMN desimper.hydro_codes_d8.dc IS 'Décalage en colonne vers la cellule aval (positif vers la droite).';


-- hydro_d8_raster
COMMENT ON TABLE desimper.hydro_d8_raster IS 'Directions d''écoulement D8 à 1 m (codes TauDEM), en tuiles. Chargées avec raster2pgsql -a.';


-- hydro_d8_raster.rid
COMMENT ON COLUMN desimper.hydro_d8_raster.rid IS 'Identifiant de la tuile.';


-- hydro_d8_raster.rast
COMMENT ON COLUMN desimper.hydro_d8_raster.rast IS 'Tuile du raster des directions D8.';


-- hydro_grille
COMMENT ON TABLE desimper.hydro_grille IS 'Grille du raster des directions D8 (une seule ligne). Une cellule a pour identifiant global lig * ncols + col. Ne doit jamais être recalculée en production : les identifiants de cellule stockés dans hydro_noeuds en dépendent.';


-- hydro_grille.x0
COMMENT ON COLUMN desimper.hydro_grille.x0 IS 'Abscisse du coin supérieur gauche de la grille.';


-- hydro_grille.y0
COMMENT ON COLUMN desimper.hydro_grille.y0 IS 'Ordonnée du coin supérieur gauche de la grille.';


-- hydro_grille.sx
COMMENT ON COLUMN desimper.hydro_grille.sx IS 'Taille d''une cellule en X (m).';


-- hydro_grille.sy
COMMENT ON COLUMN desimper.hydro_grille.sy IS 'Taille d''une cellule en Y (m), négative.';


-- hydro_grille.srid
COMMENT ON COLUMN desimper.hydro_grille.srid IS 'Système de coordonnées de la grille.';


-- hydro_grille.ncols
COMMENT ON COLUMN desimper.hydro_grille.ncols IS 'Nombre de colonnes de la grille.';


-- hydro_noeuds
COMMENT ON TABLE desimper.hydro_noeuds IS 'Nœuds du graphe hydrographique : un nœud par bassin élémentaire, relié à son nœud aval.';


-- hydro_noeuds.id
COMMENT ON COLUMN desimper.hydro_noeuds.id IS 'Identifiant du nœud : morceau * 1 000 000 + numéro TauDEM du bassin (WSNO).';


-- hydro_noeuds.piece
COMMENT ON COLUMN desimper.hydro_noeuds.piece IS 'Morceau de calcul TauDEM d''origine.';


-- hydro_noeuds.ds
COMMENT ON COLUMN desimper.hydro_noeuds.ds IS 'Nœud aval (NULL à l''exutoire).';


-- hydro_noeuds.entree
COMMENT ON COLUMN desimper.hydro_noeuds.entree IS 'Cellule d''entrée dans le nœud aval quand l''eau traverse une limite de morceau (NULL si le nœud arrive en tête du tronçon aval).';


-- hydro_noeuds.resolu
COMMENT ON COLUMN desimper.hydro_noeuds.resolu IS 'Nœud aval recherché (utilisé pendant la préparation).';


-- hydro_noeuds.geom
COMMENT ON COLUMN desimper.hydro_noeuds.geom IS 'Polygone du bassin élémentaire, densifié avec un sommet par mètre.';


-- hydro_noeuds.surf
COMMENT ON COLUMN desimper.hydro_noeuds.surf IS 'Surface du bassin élémentaire (m²).';


-- hydro_noeuds.surf_amont
COMMENT ON COLUMN desimper.hydro_noeuds.surf_amont IS 'Surface drainée par le nœud, bassins amont compris (m²).';


-- hydro_noeuds.precalc
COMMENT ON COLUMN desimper.hydro_noeuds.precalc IS 'Bassin amont précalculé dans hydro_bv_amont.';


-- hydro_troncons
COMMENT ON TABLE desimper.hydro_troncons IS 'Tronçons du réseau hydrographique TauDEM, utilisés pour recaler les points sur les cours d''eau.';


-- hydro_troncons.id
COMMENT ON COLUMN desimper.hydro_troncons.id IS 'Nœud (bassin élémentaire) du tronçon.';


-- hydro_troncons.piece
COMMENT ON COLUMN desimper.hydro_troncons.piece IS 'Morceau de calcul TauDEM d''origine.';


-- hydro_troncons.linkno
COMMENT ON COLUMN desimper.hydro_troncons.linkno IS 'Numéro TauDEM du tronçon dans son morceau.';


-- hydro_troncons.dslinkno
COMMENT ON COLUMN desimper.hydro_troncons.dslinkno IS 'Numéro TauDEM du tronçon aval dans le même morceau.';


-- hydro_troncons.geom
COMMENT ON COLUMN desimper.hydro_troncons.geom IS 'Tracé du tronçon.';


-- lignes_ecoulement
COMMENT ON TABLE desimper.lignes_ecoulement IS 'Lignes d''écoulement des projets : tracées de cellule en cellule selon les directions D8, depuis des points de départ régulièrement espacés, et prolongées au-delà du projet. Calculées avec desimper.hydro_lignes_ecoulement().';


-- lignes_ecoulement.id
COMMENT ON COLUMN desimper.lignes_ecoulement.id IS 'Identifiant unique de la ligne.';


-- lignes_ecoulement.fk_id_projet
COMMENT ON COLUMN desimper.lignes_ecoulement.fk_id_projet IS 'Projet associé à la ligne.';


-- lignes_ecoulement.depart
COMMENT ON COLUMN desimper.lignes_ecoulement.depart IS 'Identifiant de la cellule de départ de la ligne dans la grille hydrologique.';


-- lignes_ecoulement.longueur
COMMENT ON COLUMN desimper.lignes_ecoulement.longueur IS 'Longueur de la ligne (m).';


-- lignes_ecoulement.geom
COMMENT ON COLUMN desimper.lignes_ecoulement.geom IS 'Tracé de la ligne d''écoulement.';


-- lignes_ecoulement.cree_le
COMMENT ON COLUMN desimper.lignes_ecoulement.cree_le IS 'Date de calcul de la ligne.';


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


-- liste_contextes.calcul_indicateur
COMMENT ON COLUMN desimper.liste_contextes.calcul_indicateur IS 'Expression CASE/WHEN utilisé pour déterminer l''indicateur en fonction de la valeur du contexte';


-- liste_contextes.calcul_contrainte
COMMENT ON COLUMN desimper.liste_contextes.calcul_contrainte IS 'Expression CASE/WHEN utilisé pour déterminer si la valeur du contexte est une contrainte (boolean)';


-- liste_contextes.calcul_couleur
COMMENT ON COLUMN desimper.liste_contextes.calcul_couleur IS 'Expression CASE/WHEN utilisé pour déterminer la couleur de représentation du contexte en fonction de la valeur du contexte';


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



