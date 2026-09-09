# Changelog

## Unreleased

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