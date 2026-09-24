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
    REFERENCES desimper.variantes (id)
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