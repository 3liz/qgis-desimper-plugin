-- Add unique constraint on table_name in liste_contextes
ALTER TABLE desimper.liste_contextes DROP CONSTRAINT IF EXISTS liste_contextes_table_name_key;
ALTER TABLE desimper.liste_contextes ADD CONSTRAINT liste_contextes_table_name_key UNIQUE (nom_table);

-- Add login, created_at, updated_at columns
ALTER TABLE desimper.liste_contextes ADD COLUMN IF NOT EXISTS login text;
ALTER TABLE desimper.liste_contextes ADD COLUMN IF NOT EXISTS cree_le timestamp without time zone DEFAULT (now())::timestamp(0) without time zone;
ALTER TABLE desimper.liste_contextes ADD COLUMN IF NOT EXISTS modifie_le timestamp without time zone DEFAULT (now())::timestamp(0) without time zone;
COMMENT ON COLUMN desimper.liste_contextes.login IS 'Login de l''utilisateur qui a créé le contexte';
COMMENT ON COLUMN desimper.liste_contextes.cree_le IS 'Date de création du contexte';
COMMENT ON COLUMN desimper.liste_contextes.modifie_le IS 'Date de la dernière modification du contexte';

-- Replace "cree_par", "modifie_par", "cree_le", "modifie_le" with "login" in contextes_projets table
ALTER TABLE desimper.contextes_projets
    DROP COLUMN IF EXISTS fk_cree_par,
    DROP COLUMN IF EXISTS fk_modifie_par,
    ADD COLUMN IF NOT EXISTS login text,
    -- Add not null constraints
    ALTER COLUMN code_contexte SET NOT NULL,
    ALTER COLUMN id_objet_contexte SET NOT NULL
;
COMMENT ON COLUMN desimper.contextes_projets.login IS 'Login de l''utilisateur qui a créé le contexte';

ALTER TABLE desimper.projets
    DROP COLUMN IF EXISTS fk_cree_par,
    DROP COLUMN IF EXISTS fk_modifie_par,
    ADD COLUMN IF NOT EXISTS login text
;
COMMENT ON COLUMN desimper.projets.login IS 'Login de l''utilisateur qui a créé le contexte';


ALTER TABLE desimper.surfaces_projet
    DROP COLUMN IF EXISTS fk_cree_par,
    DROP COLUMN IF EXISTS fk_modifie_par,
    ADD COLUMN IF NOT EXISTS login text
;
COMMENT ON COLUMN desimper.surfaces_projet.login IS 'Login de l''utilisateur qui a créé le contexte';


ALTER TABLE desimper.variantes
    DROP COLUMN IF EXISTS fk_cree_par,
    DROP COLUMN IF EXISTS fk_modifie_par,
    ADD COLUMN IF NOT EXISTS login text
;
COMMENT ON COLUMN desimper.variantes.login IS 'Login de l''utilisateur qui a créé le contexte';


-- Function to check if a field value corresponds to the given type
DROP FUNCTION IF EXISTS desimper.is_given_type(text, text);
CREATE OR REPLACE FUNCTION desimper.is_given_type(s text, t text)
RETURNS BOOLEAN AS $BODY$
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
$BODY$ LANGUAGE plpgsql
;

COMMENT ON FUNCTION desimper.is_given_type(text, text)
IS ' Teste si la valeur d''un champ correspond au type donné. 
Retourne vrai s''il est possible de caster la valeur dans le type donné attendu.
Valeurs vides et NULL sont toujours considérées valides. 
Si le type n''est pas supporté, la valeur est considérée invalide.'
;

-- Function to fill the contextes_projets table
CREATE OR REPLACE FUNCTION desimper.fill_contextes_projets(
    id_projet integer
)
    RETURNS json
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
    FOR contexte IN SELECT nom_schema, nom_table, code 
    FROM desimper.liste_contextes
    WHERE to_regclass(format('%I.%I', nom_schema, nom_table)) IS NOT NULL -- avoid errors when a context is listed in liste_contextes but its data has not been imported yet
    LOOP
        EXECUTE format(
            $SQL$
                INSERT INTO desimper.contextes_projets
                    (fk_id_projet, geom, code_contexte, id_objet_contexte, surface_m, login)
                SELECT
                    %1$L,
                    ST_Multi(ST_CollectionExtract(ST_MakeValid(valid_contexts.geom), 3)),
                    %2$L,
                    valid_contexts.id,
                    ST_Area(valid_contexts.geom),
                    %6$L
                FROM (
                    SELECT c.id AS id,
                    ST_Multi(ST_CollectionExtract(ST_Intersection(%3$L, ST_MakeValid(c.geom)), 3)) AS geom
                    FROM %4$I.%5$I AS c
                    WHERE ST_Intersects(c.geom, %3$L)
                ) AS valid_contexts
                WHERE NOT ST_IsEmpty(valid_contexts.geom)
            $SQL$,
            id_projet, contexte.code, geom_projet, contexte.nom_schema, contexte.nom_table, login_projet
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

COMMENT ON FUNCTION desimper.fill_contextes_projets(integer) IS 'Ajoute à la table contextes_projets les contextes qui intersectent le projet';


-- Quick fixes + add type check
CREATE OR REPLACE FUNCTION desimper.import_data_from_temporary_tables(
    temp_schema text,
    temp_table text,
    label_field text,
    value_field text,
    unique_id_field text,
    code_context text
) RETURNS json
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

-- The main commune is computed by a trigger, drop the default value & the NOT NULL constraint.
ALTER TABLE desimper.projets
    ALTER COLUMN fk_commune_principale DROP DEFAULT,
    ALTER COLUMN fk_commune_principale DROP NOT NULL
;
COMMENT ON COLUMN desimper.projets.fk_commune_principale IS 'Commune principale sur laquelle se trouve le projet, déterminée automatiquement. NULL si indéterminée';


-- 
CREATE OR REPLACE FUNCTION desimper.trg_after_projet_insert_or_update()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    -- Do nothing if the geometry has not changed
    IF TG_OP = 'INSERT' OR NOT ST_Equals(NEW.geom, OLD.geom) THEN
        -- Fill the contextes_projets table
        PERFORM desimper.fill_contextes_projets(NEW.id);

        -- TO DO 
        -- Check if surface are fitting in the new project geom... 

    END IF;

    RETURN NEW;

END;
$$;

COMMENT ON FUNCTION desimper.trg_after_projet_insert_or_update()
IS 'Fonction trigger permettant de mettre à jour les tables de données métier en lien avec le projet.
Appelle desimper.fill_contextes_projets() avec l''identifiant du projet.
Ne fait rien si la géométrie du projet n''a pas changé.'
;

-- Update table contextes_projets on creation of a projet or change of its geometry.
-- The project row must be written before its contexts can be inserted.
DROP TRIGGER IF EXISTS update_contextes_projets ON desimper.projets;
CREATE TRIGGER update_contextes_projets
    AFTER INSERT OR UPDATE OF geom ON desimper.projets
    FOR EACH ROW EXECUTE FUNCTION desimper.trg_after_projet_insert_or_update()
;

-- aa_before_insert_or_update()
CREATE OR REPLACE FUNCTION desimper.aa_before_insert_or_update() RETURNS trigger
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

    RETURN NEW;
END;
$$;

-- COMMENT ON aa_before_insert_or_update()
COMMENT ON FUNCTION desimper.aa_before_insert_or_update() IS
'Met automatiquement à jour les champs suivants : cree_le, modifie_le, geom, commune_principale, surface_m';

DROP TRIGGER IF EXISTS trg_aa_before_insert_or_update ON desimper.projets;
CREATE TRIGGER trg_aa_before_insert_or_update
    BEFORE INSERT OR UPDATE ON desimper.projets
    FOR EACH ROW EXECUTE FUNCTION desimper.aa_before_insert_or_update()
;

DROP TRIGGER IF EXISTS trg_aa_before_insert_or_update ON desimper.contextes_projets;
CREATE TRIGGER trg_aa_before_insert_or_update
    BEFORE INSERT OR UPDATE ON desimper.contextes_projets
    FOR EACH ROW EXECUTE FUNCTION desimper.aa_before_insert_or_update()
;

DROP TRIGGER IF EXISTS trg_aa_before_insert_or_update ON desimper.liste_contextes;
CREATE TRIGGER trg_aa_before_insert_or_update
    BEFORE INSERT OR UPDATE ON desimper.liste_contextes
    FOR EACH ROW EXECUTE FUNCTION desimper.aa_before_insert_or_update()
;

DROP TRIGGER IF EXISTS trg_aa_before_insert_or_update ON desimper.surfaces_projet;
CREATE TRIGGER trg_aa_before_insert_or_update
    BEFORE INSERT OR UPDATE ON desimper.surfaces_projet
    FOR EACH ROW EXECUTE FUNCTION desimper.aa_before_insert_or_update()
;

DROP TRIGGER IF EXISTS trg_aa_before_insert_or_update ON desimper.variantes;
CREATE TRIGGER trg_aa_before_insert_or_update
    BEFORE INSERT OR UPDATE ON desimper.variantes
    FOR EACH ROW EXECUTE FUNCTION desimper.aa_before_insert_or_update()
;

ALTER TABLE desimper.contextes_projets
DROP CONSTRAINT IF EXISTS fk_id_projet,
ADD CONSTRAINT fk_id_projet
    FOREIGN KEY (fk_id_projet)
    REFERENCES desimper.projets (id)
    ON DELETE CASCADE;