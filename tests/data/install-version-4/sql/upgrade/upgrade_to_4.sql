-- Only autorize 1 true value for each "fk_id_projet" in the "etat_initial" field of the "variantes" table
CREATE OR REPLACE FUNCTION desimper.check_variantes_etat_initial() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        count_init_states int;
BEGIN

    IF NEW.etat_initial = false THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(fk_id_projet)
    FROM desimper.variantes
    WHERE fk_id_projet = NEW.fk_id_projet
    AND etat_initial = true
    INTO count_init_states;

    IF count_init_states != 0 THEN
        RAISE EXCEPTION 'Il est impossible d''avoir plus d''une variante représentant l''état initial du projet';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION desimper.check_variantes_etat_initial() IS 'Fonction trigger verifiant que chaque projet a seulement une variante représentant son état initial';

CREATE OR REPLACE TRIGGER check_variantes_etat_initial
    BEFORE INSERT OR UPDATE OF etat_initial
    ON desimper.variantes 
    FOR EACH ROW EXECUTE PROCEDURE desimper.check_variantes_etat_initial();

-- Drop default value from "etat_initial" field of the "variantes" table
ALTER TABLE desimper.variantes ALTER COLUMN etat_initial DROP DEFAULT;

--Drop variante when deleting a project
ALTER TABLE desimper.contextes_projets
DROP CONSTRAINT IF EXISTS fk_id_projet,
ADD CONSTRAINT fk_id_projet
    FOREIGN KEY (fk_id_projet)
    REFERENCES desimper.projets (id)
    ON DELETE CASCADE;

-- Add parent project when adding a surface to a variante
ALTER TABLE desimper.surfaces_projet ALTER COLUMN fk_id_projet SET NOT NULL;

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

-- DROP surfaces when deleting a projet
ALTER TABLE desimper.surfaces_projet
DROP CONSTRAINT IF EXISTS fk_projet_surfaces_projet,
ADD CONSTRAINT fk_projet_surfaces_projet
    FOREIGN KEY (fk_id_projet)
    REFERENCES desimper.projets (id)
    ON DELETE CASCADE;

-- Add in the "liste_contextes" table a column storing, per context, the CASE/WHEN expression
-- used to compute the constraint level from that context table's "valeur" column.
-- It is evaluated in fill_contextes_projets() to fill "contextes_projets.niveau_contrainte".
ALTER TABLE desimper.liste_contextes 
    ADD COLUMN calcul_indicateur text,
    ADD COLUMN calcul_contrainte text,
    ADD COLUMN calcul_couleur text
;

COMMENT ON COLUMN desimper.liste_contextes.calcul_indicateur IS 'Expression CASE/WHEN utilisé pour déterminer l''indicateur en fonction de la valeur du contexte';
COMMENT ON COLUMN desimper.liste_contextes.calcul_contrainte IS 'Expression CASE/WHEN utilisé pour déterminer si la valeur du contexte est une contrainte (boolean)';
COMMENT ON COLUMN desimper.liste_contextes.calcul_couleur IS 'Expression CASE/WHEN utilisé pour déterminer la couleur de représentation du contexte en fonction de la valeur du contexte';

UPDATE desimper.liste_contextes
    SET calcul_indicateur =
        $$
        CASE
            WHEN valeur = '0' THEN 'Pas de contrainte'
            WHEN valeur = '2' THEN 'Contrainte forte'
        END
        $$,
        calcul_contrainte =
        $$
        CASE
            WHEN valeur = '0' THEN False
            WHEN valeur = '2' THEN True
        END
        $$,
        calcul_couleur =
        $$
        CASE
            WHEN valeur = '0' THEN 'blue'
            WHEN valeur = '2' THEN 'red'
        END
        $$
    WHERE code = 'BAI'
;

UPDATE desimper.liste_contextes
    SET calcul_indicateur =
        $$
        CASE
            WHEN valeur = '1' THEN 'Pas de contrainte'
            WHEN valeur = '2' THEN 'Contrainte forte'
        END
        $$,
        calcul_contrainte =
        $$
        CASE
            WHEN valeur = '1' THEN False
            WHEN valeur = '2' THEN True
        END
        $$,
        calcul_couleur =
        $$
        CASE
            WHEN valeur = '0' THEN 'blue'
            WHEN valeur = '2' THEN 'red'
        END
        $$
    WHERE code = 'CHI'
;

UPDATE desimper.liste_contextes
    SET calcul_indicateur =
        $$
        CASE
            WHEN valeur = '0.5' THEN 'Contrainte faible'
            WHEN valeur = '0.95' THEN 'Contrainte forte'
            WHEN valeur = '1' THEN 'Pas de contrainte'
            WHEN valeur = '-9999' THEN 'Pas de données'
        END
        $$,
        calcul_contrainte =
        $$
        CASE
            WHEN valeur IN ('0.5', '0.95') THEN True
            WHEN valeur IN ('-9999', '1') THEN False
        END
        $$,
        calcul_couleur =
        $$
        CASE
            WHEN valeur = '0.5' THEN 'orange'
            WHEN valeur = '0.95' THEN 'yellow'
            WHEN valeur = '1' THEN 'blue'
            WHEN valeur = '-9999' THEN 'grey'
        END
        $$
    WHERE code = 'INF'
;

UPDATE desimper.liste_contextes
    SET calcul_indicateur =
        $$
        CASE
            WHEN valeur = '0.5' THEN 'Contrainte faible'
            WHEN valeur = '0.95' THEN 'Contrainte forte'
            WHEN valeur = '1' THEN 'Pas de contrainte'
            WHEN valeur = '0' THEN 'Contrainte très forte'
        END
        $$,
        calcul_contrainte =
        $$
        CASE
            WHEN valeur IN ('0.5', '0.95', '0') THEN True
            WHEN valeur IN ('1') THEN False
        END
        $$,
        calcul_couleur =
        $$
        CASE
            WHEN valeur = '0.5' THEN 'orange'
            WHEN valeur = '0.95' THEN 'yellow'
            WHEN valeur = '1' THEN 'blue'
            WHEN valeur = '0' THEN 'red'
        END
        $$
    WHERE code = 'PENTE'
;

-- Add niveau_contrainte column in the "contextes_projets" table
ALTER TABLE desimper.contextes_projets 
    ADD COLUMN indicateur text,
    ADD COLUMN est_contrainte boolean,
    ADD COLUMN couleur text
;

COMMENT ON COLUMN desimper.contextes_projets.indicateur IS 'Indicateur en fonction de la valeur du contexte';
COMMENT ON COLUMN desimper.contextes_projets.est_contrainte IS 'Indique si le contexte est une contrainte';
COMMENT ON COLUMN desimper.contextes_projets.couleur IS 'Couleur de représentation du contexte';
  

-- fill_contextes_projets(integer)
CREATE OR REPLACE FUNCTION desimper.fill_contextes_projets(id_projet integer) RETURNS json
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
