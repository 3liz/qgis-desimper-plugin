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
