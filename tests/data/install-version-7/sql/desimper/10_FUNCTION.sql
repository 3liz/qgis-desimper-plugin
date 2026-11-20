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

-- aa_before_insert_or_update()
CREATE FUNCTION desimper.aa_before_insert_or_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE newjsonb jsonb;
BEGIN

    -- Convert record to jsonb to be able to test if a field exists
    newjsonb = to_jsonb(NEW);

    -- CREE_LE / MODIFIE_LE
    IF newjsonb ? 'cree_le' THEN
        IF TG_OP = 'INSERT' THEN
            NEW.cree_le = now()::timestamp(0) without time zone;
        END IF;
    END IF;

    IF newjsonb ? 'modifie_le' THEN
        NEW.modifie_le = now()::timestamp(0) without time zone;
    END IF;

    -- GEOM / COMMUNE PRINCIPALE / SURFACE
    IF newjsonb ? 'geom' THEN
        -- Do not modify the geometry if geom field has not been changed
        IF TG_OP = 'INSERT' OR NOT (
                ST_Equals(OLD.geom, NEW.geom)
                OR
                ST_Equals(NEW.geom, ST_ReducePrecision(NEW.geom, 0.05))
            )
        THEN
            -- Reduce geometry precision
            NEW.geom = ST_ReducePrecision(NEW.geom, 0.05);

            -- Set commune principale
            IF newjsonb ? 'fk_commune_principale' THEN
                SELECT c.code_insee INTO NEW.fk_commune_principale
                FROM desimper.communes AS c
                WHERE ST_Intersects(c.geom, NEW.geom)
                ORDER BY ST_Area(
                    ST_CollectionExtract(
                        ST_Intersection(ST_MakeValid(c.geom), ST_MakeValid(NEW.geom)),
                        3
                    )
                ) DESC
                LIMIT 1;
            END IF;

            -- Set surface
            IF newjsonb ? 'surface_m' THEN
                NEW.surface_m = ST_Area(NEW.geom);
            END IF;
        END IF;
    END IF;

    -- Set parent project with surfaces
    IF newjsonb ? 'fk_id_projet' AND TG_TABLE_NAME = 'surfaces_projet' THEN
        SELECT p.fk_id_projet INTO NEW.fk_id_projet
        FROM desimper.variantes AS p
        WHERE p.id = NEW.fk_id_variante
        LIMIT 1;
    END IF;

    RETURN NEW;
END;
$$;


-- FUNCTION aa_before_insert_or_update()
COMMENT ON FUNCTION desimper.aa_before_insert_or_update() IS 'Met automatiquement à jour les champs suivants : cree_le, modifie_le, geom, commune_principale, surface_m';


-- calculer_bassin_versant(integer)
CREATE FUNCTION desimper.calculer_bassin_versant(id_projet integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    projet_geom geometry;
    bv_geom geometry;
    bv_id integer;
BEGIN

    -- The hydro functions are installed apart from this plugin
    IF to_regprocedure('hydro.bassin_polygone(geometry,double precision)') IS NULL THEN
        RAISE EXCEPTION 'La fonction hydro.bassin_polygone(geometry, double precision) est absente de la base : impossible de calculer le bassin versant.';
    END IF;

    SELECT p.geom INTO projet_geom
    FROM desimper.projets AS p
    WHERE p.id = id_projet;

    IF projet_geom IS NULL THEN
        RAISE EXCEPTION 'Le projet % n''existe pas.', id_projet;
    END IF;

    -- Watershed of the project polygon (project included), simplified at 1 m
    bv_geom = ST_Multi(ST_CollectionExtract(hydro.bassin_polygone(projet_geom, 1), 3));

    IF bv_geom IS NULL OR ST_IsEmpty(bv_geom) THEN
        RAISE EXCEPTION 'Le bassin versant du projet % n''a pas pu être calculé (projet hors des données hydrologiques ?).', id_projet;
    END IF;

    INSERT INTO desimper.bassins_versants (fk_id_projet, corrige, geom)
    VALUES (id_projet, false, bv_geom)
    ON CONFLICT (fk_id_projet, corrige)
    DO UPDATE SET geom = EXCLUDED.geom
    RETURNING id INTO bv_id;

    RETURN json_build_object(
        'type', 'FeatureCollection',
        'features', json_build_array(
            json_build_object(
                'type', 'Feature',
                'id', bv_id,
                'geometry', ST_AsGeoJSON(bv_geom)::json,
                'properties', json_build_object(
                    'id', bv_id,
                    'fk_id_projet', id_projet,
                    'corrige', false
                )
            )
        )
    );
END;
$$;


-- FUNCTION calculer_bassin_versant(id_projet integer)
COMMENT ON FUNCTION desimper.calculer_bassin_versant(id_projet integer) IS 'Calcule (ou recalcule) le bassin versant automatique d''un projet avec hydro.bassin_polygone() et l''enregistre dans bassins_versants avec corrige = false.
Le bassin versant corrigé par l''utilisateur n''est pas modifié.
Renvoie le bassin versant en GeoJSON (FeatureCollection).';


-- calculer_ecoulements(integer, double precision, double precision, double precision)
CREATE FUNCTION desimper.calculer_ecoulements(id_projet integer, pas_fleches double precision DEFAULT 5, espacement_lignes double precision DEFAULT 10, marge_lignes double precision DEFAULT 50) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    projet_geom geometry;
    nb_fleches integer;
    nb_lignes integer;
BEGIN

    -- The hydro functions are installed apart from this plugin
    IF to_regprocedure('hydro.fleches_ecoulement(geometry,double precision)') IS NULL
        OR to_regprocedure('hydro.lignes_ecoulement(geometry,double precision,double precision)') IS NULL
    THEN
        RAISE EXCEPTION 'Les fonctions hydro.fleches_ecoulement(geometry, double precision) et hydro.lignes_ecoulement(geometry, double precision, double precision) sont absentes de la base : impossible de calculer les écoulements.';
    END IF;

    SELECT p.geom INTO projet_geom
    FROM desimper.projets AS p
    WHERE p.id = id_projet;

    IF projet_geom IS NULL THEN
        RAISE EXCEPTION 'Le projet % n''existe pas.', id_projet;
    END IF;

    -- Replace the previous computation
    DELETE FROM desimper.fleches_ecoulement AS f
    WHERE f.fk_id_projet = id_projet;

    DELETE FROM desimper.lignes_ecoulement AS l
    WHERE l.fk_id_projet = id_projet;

    -- Flow arrows
    INSERT INTO desimper.fleches_ecoulement (fk_id_projet, angle, coherence, nb_cellules, geom)
    SELECT id_projet, f.angle, f.coherence, f.nb_cellules, ST_Transform(f.geom, 2154)
    FROM hydro.fleches_ecoulement(projet_geom, pas_fleches) AS f
    WHERE f.geom IS NOT NULL
    AND f.angle IS NOT NULL;

    GET DIAGNOSTICS nb_fleches = ROW_COUNT;

    -- Flow lines
    INSERT INTO desimper.lignes_ecoulement (fk_id_projet, depart, longueur, geom)
    SELECT id_projet, l.depart, l.longueur, ST_Transform(l.geom, 2154)
    FROM hydro.lignes_ecoulement(projet_geom, espacement_lignes, marge_lignes) AS l
    WHERE GeometryType(l.geom) = 'LINESTRING';

    GET DIAGNOSTICS nb_lignes = ROW_COUNT;

    RETURN json_build_object(
        'fk_id_projet', id_projet,
        'nb_fleches', nb_fleches,
        'nb_lignes', nb_lignes
    );
END;
$$;


-- FUNCTION calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision)
COMMENT ON FUNCTION desimper.calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision) IS 'Calcule (ou recalcule) les flèches et les lignes d''écoulement d''un projet avec hydro.fleches_ecoulement() et hydro.lignes_ecoulement(), et les enregistre dans fleches_ecoulement et lignes_ecoulement.
Paramètres : taille des mailles des flèches (m), espacement des départs des lignes (m), prolongement des lignes au-delà du projet (m).
Renvoie le nombre de flèches et de lignes enregistrées.';


-- creer_bassin_versant_corrige(integer)
CREATE FUNCTION desimper.creer_bassin_versant_corrige(id_projet integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    bv_id integer;
BEGIN

    -- The corrected watershed already exists
    SELECT bv.id INTO bv_id
    FROM desimper.bassins_versants AS bv
    WHERE bv.fk_id_projet = id_projet
    AND bv.corrige;

    IF bv_id IS NOT NULL THEN
        RETURN bv_id;
    END IF;

    -- Copy the automatic watershed
    INSERT INTO desimper.bassins_versants (fk_id_projet, corrige, geom)
    SELECT bv.fk_id_projet, true, bv.geom
    FROM desimper.bassins_versants AS bv
    WHERE bv.fk_id_projet = id_projet
    AND NOT bv.corrige
    RETURNING id INTO bv_id;

    IF bv_id IS NULL THEN
        RAISE EXCEPTION 'Le projet % n''a pas de bassin versant calculé automatiquement à corriger.', id_projet;
    END IF;

    RETURN bv_id;
END;
$$;


-- FUNCTION creer_bassin_versant_corrige(id_projet integer)
COMMENT ON FUNCTION desimper.creer_bassin_versant_corrige(id_projet integer) IS 'Crée le bassin versant corrigé (corrige = true) d''un projet en copiant son bassin versant automatique.
Ne fait rien s''il existe déjà.
Renvoie l''identifiant du bassin versant corrigé.';


-- fill_contextes_projets(integer)
CREATE FUNCTION desimper.fill_contextes_projets(id_projet integer) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE 
    contexte record;
    geom_projet geometry;
    login_projet text;
BEGIN

    -- Check if id projet exist
    IF (SELECT COUNT(*) FROM desimper.projets WHERE id = id_projet) = 0 THEN
        RETURN json_build_object(
            'status', 'error',
            'message', 'Le projet passé en paramètre n''existe pas'
        );
    END IF;
    
    -- Get the geom and the login of the project
    SELECT ST_CollectionExtract(ST_MakeValid(geom), 3), login
    INTO geom_projet, login_projet
    FROM desimper.projets WHERE id = id_projet;

    -- Clear the table 
    DELETE FROM desimper.contextes_projets WHERE fk_id_projet = id_projet;

    -- Reset the sequence
    PERFORM setval(
        pg_get_serial_sequence('desimper.contextes_projets', 'id'),
        COALESCE((SELECT MAX(id) FROM desimper.contextes_projets), 0) + 1,
        false
    );   

    -- Loop to add all context who intersect the project
    FOR contexte IN SELECT nom_schema, nom_table, code, calcul_indicateur, calcul_contrainte, calcul_couleur
    FROM desimper.liste_contextes
    WHERE to_regclass(format('%I.%I', nom_schema, nom_table)) IS NOT NULL -- avoid errors when a context is listed in liste_contextes but its data has not been imported yet
    LOOP
        EXECUTE format(
            $SQL$
                INSERT INTO desimper.contextes_projets
                    (fk_id_projet, geom, code_contexte, id_objet_contexte, surface_m, login, indicateur, est_contrainte, couleur)
                SELECT
                    %1$L,
                    ST_Multi(ST_CollectionExtract(ST_MakeValid(valid_contexts.geom), 3)),
                    %2$L,
                    valid_contexts.id,
                    ST_Area(valid_contexts.geom),
                    %6$L,
                    (%7$s),
                    (%8$s),
                    (%9$s)
                FROM (
                    SELECT c.id AS id,
                    c.valeur AS valeur,
                    ST_Multi(ST_CollectionExtract(ST_Intersection(%3$L, ST_MakeValid(c.geom)), 3)) AS geom
                    FROM %4$I.%5$I AS c
                    WHERE ST_Intersects(c.geom, %3$L)
                ) AS valid_contexts
                WHERE NOT ST_IsEmpty(valid_contexts.geom)
            $SQL$,
            id_projet, contexte.code, geom_projet, contexte.nom_schema, contexte.nom_table, login_projet,
            COALESCE(contexte.calcul_indicateur, 'NULL'),
            COALESCE(contexte.calcul_contrainte, 'NULL'),
            COALESCE(contexte.calcul_couleur, 'NULL')
        );
    END LOOP;

    RETURN json_build_object(
            'status', 'success',
            'message', 'ok',
            'rows_inserted', (SELECT COUNT(*) FROM desimper.contextes_projets WHERE fk_id_projet = id_projet),
            'contexts_intersected', (SELECT COUNT(DISTINCT(code_contexte)) FROM desimper.contextes_projets WHERE fk_id_projet = id_projet)
    );

END;
$_$;


-- FUNCTION fill_contextes_projets(id_projet integer)
COMMENT ON FUNCTION desimper.fill_contextes_projets(id_projet integer) IS 'Ajoute à la table contextes_projets les contextes qui intersectent le projet';


-- import_data_from_temporary_tables(text, text, text, text, text, text)
CREATE FUNCTION desimper.import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE
    target_schema text;
    target_table text;
    expected_type text;
    invalid_number integer;
    invalid_details text;
BEGIN

    -- Get the target table, schema and expected value type from the context list
    EXECUTE format(
        $SQL$
            SELECT nom_schema, nom_table, type_valeur
            FROM desimper.liste_contextes
            WHERE code = %1$L
        $SQL$,
        code_context
    )
    INTO target_schema, target_table, expected_type;

    -- Check if target table exist
    IF target_table IS NULL THEN
        RETURN json_build_object(
            'status', 'error',
            'message', format('Aucune table cible pour le contexte %s', code_context)
        );
    END IF;

    -- Check if data type is the one expected
    EXECUTE format(
        $SQL$
            -- Get invalid values
            WITH invalid_values AS (
                SELECT %3$I::text AS id_object, %4$I::text AS value
                FROM %1$I.%2$I
                WHERE NOT desimper.is_given_type(%4$I::text, %5$L)
            )
            SELECT
                -- Number of invalid values
                (SELECT count(*) FROM invalid_values),
                -- List of invalid values
                (
                    SELECT string_agg('L''objet ' || id_object || ' a la valeur "' || coalesce(value, 'NULL') || '"', E'\n' ORDER BY id_object)
                    FROM (SELECT * FROM invalid_values ORDER BY id_object LIMIT 10) AS extract
                )
        $SQL$,
        temp_schema,
        temp_table,
        unique_id_field,
        value_field,
        expected_type
    )
    INTO invalid_number, invalid_details;

    -- Return error if there are invalid values
    IF invalid_number > 0 THEN
        IF invalid_number > 10 THEN
            invalid_details := invalid_details || format(', … (%s autres)', invalid_number - 10);
        END IF;
        RETURN json_build_object(
            'status', 'error',
            'message', format(
                'Les valeurs du champ %s doivent être de type %s pour le contexte %s',
                value_field, expected_type, code_context
            ),
            'data', json_build_object(
                'number', invalid_number,
                'details', invalid_details
            )
        );
    END IF;

    -- Drop table before creating a new one
    EXECUTE format(
        'DROP TABLE IF EXISTS %1$I.%2$I CASCADE',
        target_schema,
        target_table
    );

    -- Create new table
    EXECUTE format(
        $SQL$
            CREATE TABLE %1$I.%2$I (
                id integer NOT NULL GENERATED BY DEFAULT AS IDENTITY,
                unique_object_id text NOT NULL,
                geom geometry(MultiPolygon,2154) NOT NULL,
                fk_code_liste_contextes text,
                CONSTRAINT fk_code_liste_contextes FOREIGN KEY (fk_code_liste_contextes) REFERENCES desimper.liste_contextes(code),
                libelle text,
                valeur text
            )
        $SQL$,
        target_schema,
        target_table
    );    
    -- Comment on table
    -- example :
    -- id | unique_object_id | geom | fk_code_liste_contextes | libelle   | valeur
    -- 1  | 1 | MULTIPOLYGON(...)   | 'BAI' | 'Pas de site de baignade'   | 0
    -- 2  | 1 | MULTIPOLYGON(...)   | 'BAI' | 'Pas de site de baignade'   | 0
    -- 3  | 2 | MULTIPOLYGON(...)   | 'BAI' | 'Site de baignade à l'aval' | 2
    EXECUTE format(
        $SQL$
            COMMENT ON TABLE %1$I.%2$I IS %3$L;
            COMMENT ON COLUMN %1$I.%2$I.id IS 'Identifiant automatique de l''objet';
            COMMENT ON COLUMN %1$I.%2$I.unique_object_id IS 'Identifiant unique de l''objet avant la subdivision';
            COMMENT ON COLUMN %1$I.%2$I.geom IS 'Geométrie';
            COMMENT ON COLUMN %1$I.%2$I.fk_code_liste_contextes IS 'Référence le code du contexte dans la liste des contextes';
            COMMENT ON COLUMN %1$I.%2$I.libelle IS 'Libellé';
            COMMENT ON COLUMN %1$I.%2$I.valeur IS 'Valeur';
        $SQL$,
        target_schema,
        target_table,
        format('Table contenant les données pour le contexte %s', code_context)
    );

    -- Indexes : 
    -- on foreign key
    EXECUTE format(
        $SQL$
            CREATE INDEX ON %1$I.%2$I (fk_code_liste_contextes);
        $SQL$,
        target_schema,
        target_table
    );
    --on geom
    EXECUTE format(
        $SQL$
            CREATE INDEX ON %1$I.%2$I USING GIST (geom);
        $SQL$,
        target_schema,
        target_table
    );

    -- View for layer display in QGIS
    EXECUTE format(
        $SQL$
            CREATE VIEW %1$I.%2$I AS
            SELECT 
                row_number() OVER ()::integer AS id, 
                unique_object_id, ST_Union(geom) AS geom, 
                fk_code_liste_contextes, libelle, valeur
            FROM %3$I.%4$I
            GROUP BY unique_object_id, fk_code_liste_contextes, libelle, valeur
        $SQL$,
        target_schema,
        concat('v_', target_table),
        target_schema,
        target_table
    );

    -- Divide the geometries and insert data
    EXECUTE format(
        $SQL$
            INSERT INTO %1$I.%2$I (unique_object_id, geom, fk_code_liste_contextes, libelle, valeur)
            SELECT %8$I, ST_Multi(ST_Subdivide(ST_CollectionExtract(ST_MakeValid(geom), 3))), %3$L, %4$I, %5$I
            FROM %6$I.%7$I
        $SQL$,
        target_schema,
        target_table,
        code_context,
        label_field,
        value_field,
        temp_schema,
        temp_table,
        unique_id_field
    );

    RETURN json_build_object(
            'status', 'success',
            'message', 'ok'
        );

END;
$_$;


-- FUNCTION import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text)
COMMENT ON FUNCTION desimper.import_data_from_temporary_tables(temp_schema text, temp_table text, label_field text, value_field text, unique_id_field text, code_context text) IS 'Import data from temporary tables into schema and table defined in desimper.liste_contextes';


-- is_given_type(text, text)
CREATE FUNCTION desimper.is_given_type(s text, t text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Avoid to test empty strings
    s = Nullif(s, '');
    IF s IS NULL THEN
        return true;
    END IF;

    -- The expected type comes from user filled data, normalize it
    -- otherwise 'Integer' or 'integer ' would silently fall into the ELSE branch
    t = lower(btrim(t));

    -- Test to cast the string to the given type
    IF t = 'date' THEN
        PERFORM s::date;
        RETURN true;
    ELSIF t = 'time' THEN
        PERFORM s::time;
        RETURN true;
    ELSIF t = 'timestamp' THEN
        PERFORM CAST(s AS timestamp);
        RETURN true;
    ELSIF t = 'integer' THEN
        PERFORM s::integer;
        RETURN true;
    ELSIF t = 'real' THEN
        PERFORM s::real;
        RETURN true;
    ELSIF t = 'text' THEN
        PERFORM s::text;
        RETURN true;
    ELSIF t = 'boolean' THEN
        PERFORM s::boolean;
        RETURN true;
    ELSIF t = 'uuid' THEN
        PERFORM s::uuid;
        RETURN true;
    ELSIF t = 'wkt' THEN
        PERFORM (ST_GeomFromText(s))::geometry;
        RETURN true;
    ELSE
        -- Unsupported type: consider the value as invalid
        -- Prevent silent errors when the user enters a wrong type
        RETURN false;
    END IF;
EXCEPTION WHEN others THEN
    return false;
END;
$$;


-- FUNCTION is_given_type(s text, t text)
COMMENT ON FUNCTION desimper.is_given_type(s text, t text) IS ' Teste si la valeur d''un champ correspond au type donné. 
Retourne vrai s''il est possible de caster la valeur dans le type donné attendu.
Valeurs vides et NULL sont toujours considérées valides. 
Si le type n''est pas supporté, la valeur est considérée invalide.';


-- set_variantes_etat_initial()
CREATE FUNCTION desimper.set_variantes_etat_initial() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- The value is set at creation and cannot be changed afterwards,
    -- unless the variant is moved to another project
    IF TG_OP = 'UPDATE' AND NEW.fk_id_projet = OLD.fk_id_projet THEN
        NEW.etat_initial = OLD.etat_initial;
        RETURN NEW;
    END IF;

    -- The variant is the initial state if its project does not have one yet
    NEW.etat_initial = NOT EXISTS (
        SELECT 1
        FROM desimper.variantes AS v
        WHERE v.fk_id_projet = NEW.fk_id_projet
        AND v.etat_initial
        AND v.id IS DISTINCT FROM NEW.id
    );

    RETURN NEW;
END;
$$;


-- FUNCTION set_variantes_etat_initial()
COMMENT ON FUNCTION desimper.set_variantes_etat_initial() IS 'Fonction trigger calculant le champ etat_initial des variantes : vrai si le projet n''a pas encore de variante représentant son état initial, faux sinon.
La valeur envoyée par le client est ignorée. Elle n''est plus modifiée après la création, sauf si la variante change de projet.';


-- trg_after_projet_insert_or_update()
CREATE FUNCTION desimper.trg_after_projet_insert_or_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- Do nothing if the geometry has not changed
    IF TG_OP = 'INSERT' OR NOT ST_Equals(NEW.geom, OLD.geom) THEN
        -- Fill the contextes_projets table
        PERFORM desimper.fill_contextes_projets(NEW.id);

        IF TG_OP = 'UPDATE' THEN
            -- The automatic watershed is not valid anymore
            -- The corrected one is kept
            DELETE FROM desimper.bassins_versants
            WHERE fk_id_projet = NEW.id
            AND NOT corrige;

            -- The flow arrows and lines are not valid anymore
            DELETE FROM desimper.fleches_ecoulement
            WHERE fk_id_projet = NEW.id;

            DELETE FROM desimper.lignes_ecoulement
            WHERE fk_id_projet = NEW.id;
        END IF;

        -- TO DO
        -- Check if surface are fitting in the new project geom...

    END IF;

    RETURN NEW;

END;
$$;


-- FUNCTION trg_after_projet_insert_or_update()
COMMENT ON FUNCTION desimper.trg_after_projet_insert_or_update() IS 'Fonction trigger permettant de mettre à jour les tables de données métier en lien avec le projet.
Appelle desimper.fill_contextes_projets() avec l''identifiant du projet.
Supprime le bassin versant automatique du projet (le bassin versant corrigé est conservé), ainsi que ses flèches et lignes d''écoulement.
Ne fait rien si la géométrie du projet n''a pas changé.';


--
-- PostgreSQL database dump complete
--



