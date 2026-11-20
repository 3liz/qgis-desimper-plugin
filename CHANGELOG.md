# Changelog

## Unreleased

## 0.4.0 - 2026-11-20

### Added

* Database schema versions 4 to 8
* Watersheds
    * New table `bassins_versants`: at most two watersheds per project (the automatic one and a corrected one)
    * New functions `calculer_bassin_versant()` and `creer_bassin_versant_corrige()`
* Flow arrows and flow lines
    * New tables `fleches_ecoulement` and `lignes_ecoulement`
    * New function `calculer_ecoulements()`
* Hydrological elements integrated in the main schema (requires the `postgis_raster` extension)
    * New tables `hydro_grille`, `hydro_codes_d8`, `hydro_d8_raster`, `hydro_noeuds`, `hydro_troncons`
      and `hydro_bv_amont`, holding the D8 raster and the hydrographic graph
    * New `hydro_*` functions computing watersheds and flows (`hydro_bassin_point`, `hydro_bassin_versant`,
      `hydro_bassin_polygone`, `hydro_fleches_ecoulement`, `hydro_lignes_ecoulement`…)
* Add columns `calcul_indicateur`, `calcul_contrainte` and `calcul_couleur` to `liste_contextes`, and columns
  `indicateur`, `est_contrainte` and `couleur` to `contextes_projets`, filled by `fill_contextes_projets()`

### Changed

* `trg_after_projet_insert_or_update()` now deletes the automatic watershed, flow arrows and flow lines of a project when its geometry changes (the corrected watershed is kept)
* `etat_initial` of the variants is now computed by the database (trigger `set_variantes_etat_initial`) instead of
  only being checked, with a unique index guaranteeing a single initial state per project
* `surfaces_projet.fk_id_projet` is now `NOT NULL` and set automatically from the variant
* Surfaces and variants are now deleted when their project is deleted
* Drop the default value of `variantes.etat_initial`

### Removed

* Drop the unique constraint on `variantes.libelle`: two projects can have variants with the same name

## 0.3.0 - 2026-09-09

### Added

* Add function to fill `contextes_projets` table & corresponding tests
* Add data type verification to the function `import_data_from_temporary_table`
* Add triggers & functions to :
  * aa_before_insert_or_update() => fill automatics fields, reduce geom precision to 5cm
  * trg_after_projet_insert_or_update() => fill the contextes_projets table when project is created or updated
* Add option to automatically add contexts layers to the local interface

### Changed 

* Update the plugin icon
* Merge fields `cree_par` & `modifie_par` in `login`
* Update fk_id_projet constraint on contextes_projets table in order to also delete contextes_projets when a projet is deleted

### Fixed

* Fix error when a context is listed in liste_contextes but its data has not been imported yet


## 0.2.0 - 2026-08-04

### Added

* Import context data from an external layer
    * New processing algorithm `import_context_data`
    * New SQL function `import_data_from_temporary_tables()`, which creates the
      target table and view on demand

### Changed

* Database schema version 2
    * `liste_contextes.nom_schema` and `nom_table` are now `VARCHAR(50)` and `NOT NULL`
    * `liste_contextes.type_geom` has been dropped
* Update the plugin icon
* Build SQL queries with `psycopg2.sql` composition instead of f-strings,
  preventing SQL injection

### Removed

* The `contexte_baignade` and `contexte_mouvement_terrain` tables are no longer
  part of the default structure.

### Fixed

* Fix documentation links


## 0.1.0 - 2026-06-10

* First version of the plugin