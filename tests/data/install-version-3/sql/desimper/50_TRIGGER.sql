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

-- contextes_projets trg_aa_before_insert_or_update
CREATE TRIGGER trg_aa_before_insert_or_update BEFORE INSERT OR UPDATE ON desimper.contextes_projets FOR EACH ROW EXECUTE PROCEDURE desimper.aa_before_insert_or_update();


-- liste_contextes trg_aa_before_insert_or_update
CREATE TRIGGER trg_aa_before_insert_or_update BEFORE INSERT OR UPDATE ON desimper.liste_contextes FOR EACH ROW EXECUTE PROCEDURE desimper.aa_before_insert_or_update();


-- projets trg_aa_before_insert_or_update
CREATE TRIGGER trg_aa_before_insert_or_update BEFORE INSERT OR UPDATE ON desimper.projets FOR EACH ROW EXECUTE PROCEDURE desimper.aa_before_insert_or_update();


-- surfaces_projet trg_aa_before_insert_or_update
CREATE TRIGGER trg_aa_before_insert_or_update BEFORE INSERT OR UPDATE ON desimper.surfaces_projet FOR EACH ROW EXECUTE PROCEDURE desimper.aa_before_insert_or_update();


-- variantes trg_aa_before_insert_or_update
CREATE TRIGGER trg_aa_before_insert_or_update BEFORE INSERT OR UPDATE ON desimper.variantes FOR EACH ROW EXECUTE PROCEDURE desimper.aa_before_insert_or_update();


-- projets update_contextes_projets
CREATE TRIGGER update_contextes_projets AFTER INSERT OR UPDATE OF geom ON desimper.projets FOR EACH ROW EXECUTE PROCEDURE desimper.trg_after_projet_insert_or_update();


--
-- PostgreSQL database dump complete
--



