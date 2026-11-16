-- Drop unique constraint on variantes.libelle (It's possible to have 2 variants with the same name in different projects)
ALTER TABLE ONLY desimper.variantes
    DROP CONSTRAINT variantes_libelle_key;

-- Compute "etat_initial" of variants in the database instead of only checking it.
-- Client default values cannot be trusted (Lizmap evaluates them before knowing the parent project)
DROP TRIGGER IF EXISTS check_variantes_etat_initial ON desimper.variantes;
DROP FUNCTION IF EXISTS desimper.check_variantes_etat_initial();

CREATE OR REPLACE FUNCTION desimper.set_variantes_etat_initial() RETURNS trigger
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

COMMENT ON FUNCTION desimper.set_variantes_etat_initial() IS 'Fonction trigger calculant le champ etat_initial des variantes : vrai si le projet n''a pas encore de variante représentant son état initial, faux sinon.
La valeur envoyée par le client est ignorée. Elle n''est plus modifiée après la création, sauf si la variante change de projet.';

CREATE TRIGGER set_variantes_etat_initial
    BEFORE INSERT OR UPDATE OF etat_initial, fk_id_projet ON desimper.variantes
    FOR EACH ROW EXECUTE PROCEDURE desimper.set_variantes_etat_initial();

-- Guarantee at most one initial state per project (e.g. concurrent inserts)
CREATE UNIQUE INDEX variantes_fk_id_projet_etat_initial_idx
    ON desimper.variantes USING btree (fk_id_projet)
    WHERE etat_initial;
