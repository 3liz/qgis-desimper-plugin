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

    -- The hydrological data are loaded apart from this plugin
    IF NOT EXISTS (SELECT 1 FROM desimper.hydro_grille) THEN
        RAISE EXCEPTION 'Les données hydrologiques (tables hydro_*) ne sont pas chargées : impossible de calculer le bassin versant.';
    END IF;

    SELECT p.geom INTO projet_geom
    FROM desimper.projets AS p
    WHERE p.id = id_projet;

    IF projet_geom IS NULL THEN
        RAISE EXCEPTION 'Le projet % n''existe pas.', id_projet;
    END IF;

    -- Watershed of the project polygon (project included), simplified at 1 m
    bv_geom = ST_Multi(ST_CollectionExtract(desimper.hydro_bassin_polygone(projet_geom, 1), 3));

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
COMMENT ON FUNCTION desimper.calculer_bassin_versant(id_projet integer) IS 'Calcule (ou recalcule) le bassin versant automatique d''un projet avec desimper.hydro_bassin_polygone() et l''enregistre dans bassins_versants avec corrige = false.
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

    -- The hydrological data are loaded apart from this plugin
    IF NOT EXISTS (SELECT 1 FROM desimper.hydro_grille) THEN
        RAISE EXCEPTION 'Les données hydrologiques (tables hydro_*) ne sont pas chargées : impossible de calculer les écoulements.';
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
    FROM desimper.hydro_fleches_ecoulement(projet_geom, pas_fleches) AS f
    WHERE f.geom IS NOT NULL
    AND f.angle IS NOT NULL;

    GET DIAGNOSTICS nb_fleches = ROW_COUNT;

    -- Flow lines
    INSERT INTO desimper.lignes_ecoulement (fk_id_projet, depart, longueur, geom)
    SELECT id_projet, l.depart, l.longueur, ST_Transform(l.geom, 2154)
    FROM desimper.hydro_lignes_ecoulement(projet_geom, espacement_lignes, marge_lignes) AS l
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
COMMENT ON FUNCTION desimper.calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision) IS 'Calcule (ou recalcule) les flèches et les lignes d''écoulement d''un projet avec desimper.hydro_fleches_ecoulement() et desimper.hydro_lignes_ecoulement(), et les enregistre dans fleches_ecoulement et lignes_ecoulement.
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


-- hydro_bassin_point(geometry, double precision)
CREATE FUNCTION desimper.hydro_bassin_point(p_point geometry, p_rayon double precision DEFAULT 0) RETURNS geometry
    LANGUAGE plpgsql
    SET enable_hashjoin TO 'off'
    SET enable_mergejoin TO 'off'
    AS $$
DECLARE
    g         desimper.hydro_grille%ROWTYPE;
    v_snap    geometry;
    v_lig     int;
    v_col     int;
    v_centre  geometry;
    v_depart  bigint;
    v_noeud   bigint;
    v_elem    geometry;
    v_entrants bigint[];
    v_partiel  geometry;
    v_res      geometry;
    v_fenetre  double precision := 1000;   -- demi-largeur de la fenêtre hors nœud (m)
BEGIN
    SELECT * INTO g FROM desimper.hydro_grille;
    IF ST_SRID(p_point) <> g.srid THEN
        p_point := ST_Transform(p_point, g.srid);
    END IF;

    -- 1. Recalage sur un sommet du réseau (= centre d'une cellule de cours d'eau)
    v_lig := floor((ST_Y(p_point) - g.y0) / g.sy);
    v_col := floor((ST_X(p_point) - g.x0) / g.sx);
    v_centre := ST_SetSRID(ST_MakePoint(g.x0 + (v_col + 0.5) * g.sx,
                                        g.y0 + (v_lig + 0.5) * g.sy), g.srid);

    SELECT dp.geom INTO v_snap
    FROM desimper.hydro_troncons t
    CROSS JOIN LATERAL ST_DumpPoints(t.geom) dp
    WHERE ST_DWithin(t.geom, p_point, greatest(p_rayon, abs(g.sx)))
      AND (ST_DWithin(dp.geom, p_point, p_rayon)
           OR ST_DWithin(dp.geom, v_centre, abs(g.sx) / 100))
    ORDER BY ST_Distance(dp.geom, p_point)
    LIMIT 1;

    IF v_snap IS NOT NULL THEN
        v_lig := floor((ST_Y(v_snap) - g.y0) / g.sy);
        v_col := floor((ST_X(v_snap) - g.x0) / g.sx);
        v_centre := ST_SetSRID(ST_MakePoint(g.x0 + (v_col + 0.5) * g.sx,
                                            g.y0 + (v_lig + 0.5) * g.sy), g.srid);
    END IF;
    v_depart := v_lig::bigint * g.ncols + v_col;

    -- 2. Nœud (bassin élémentaire) contenant la cellule de départ.
    --    Hors de tout nœud (petits bassins côtiers ou îlots sans cours d'eau de plus
    --    de SEUIL_FIN), le bassin est petit et entièrement en zone non couverte :
    --    on le calcule dans une fenêtre autour du point, agrandie si besoin.
    SELECT n.id, n.geom INTO v_noeud, v_elem
    FROM desimper.hydro_noeuds n
    WHERE ST_Intersects(n.geom, v_centre)
    LIMIT 1;

    LOOP
        IF v_noeud IS NULL THEN
            v_elem := ST_Expand(v_centre, v_fenetre);
        END IF;

        -- 3. Cellules fines de la zone de calcul (lecture du COG limitée à son emprise)
        DROP TABLE IF EXISTS pg_temp.bv_cel;
        CREATE TEMP TABLE bv_cel AS
        SELECT px.id,
               CASE WHEN c.code IS NOT NULL
                     AND px.col + c.dc BETWEEN 0 AND g.ncols - 1
                    THEN px.id + c.dl * g.ncols + c.dc
               END AS down_id
        FROM desimper.hydro_d8_raster t
        CROSS JOIN LATERAL desimper.hydro_pixels(ST_Clip(t.rast, 1, v_elem, true)) px
        LEFT JOIN desimper.hydro_codes_d8 c ON c.code = px.val::int
        WHERE t.rast && v_elem
          AND ST_Intersects(ST_ConvexHull(t.rast), v_elem);   -- évite les tuiles seulement voisines
        CREATE INDEX ON bv_cel (down_id);
        ANALYZE bv_cel;

        -- Point en mer, dans un plan d'eau masqué ou hors données
        IF NOT EXISTS (SELECT 1 FROM bv_cel WHERE id = v_depart) THEN
            DROP TABLE pg_temp.bv_cel;
            RAISE NOTICE 'Point hors des données (mer, plan d''eau masqué ou hors MNT)';
            RETURN NULL;
        END IF;

        -- 4. Remontée
        DROP TABLE IF EXISTS pg_temp.bv_amont_cel;
        CREATE TEMP TABLE bv_amont_cel AS
        WITH RECURSIVE amont(id) AS (
            SELECT v_depart
            UNION
            SELECT c.id FROM bv_cel c JOIN amont a ON c.down_id = a.id
        )
        SELECT id FROM amont;
        CREATE INDEX ON bv_amont_cel (id);

        -- 5. Polygone de la partie fine, par segments de ligne
        WITH cel AS (
            SELECT (id / g.ncols)::int AS lig, (id % g.ncols)::int AS col FROM bv_amont_cel
        ), segments AS (
            SELECT lig, min(col) AS c1, max(col) AS c2
            FROM (SELECT lig, col,
                         col - row_number() OVER (PARTITION BY lig ORDER BY col) AS grp
                  FROM cel) s
            GROUP BY lig, grp
        )
        SELECT ST_Union(ST_MakeEnvelope(
                   g.x0 + c1 * g.sx,       g.y0 + (lig + 1) * g.sy,
                   g.x0 + (c2 + 1) * g.sx, g.y0 + lig * g.sy,
                   g.srid))
        INTO v_partiel
        FROM segments;

        -- Dans un nœud : terminé. Hors nœud : le bassin doit être entièrement
        -- à l'intérieur de la fenêtre, sinon on l'agrandit.
        EXIT WHEN v_noeud IS NOT NULL;
        EXIT WHEN ST_XMin(v_partiel) > ST_XMin(v_elem) + abs(g.sx)
              AND ST_XMax(v_partiel) < ST_XMax(v_elem) - abs(g.sx)
              AND ST_YMin(v_partiel) > ST_YMin(v_elem) + abs(g.sx)
              AND ST_YMax(v_partiel) < ST_YMax(v_elem) - abs(g.sx);
        IF v_fenetre >= 4000 THEN
            RAISE NOTICE 'Bassin hors nœud plus grand que la fenêtre maximale : résultat tronqué';
            EXIT;
        END IF;
        v_fenetre := v_fenetre * 2;
    END LOOP;

    -- 6. Nœuds qui se jettent dans le bassin élémentaire en amont du point
    --    (aucun si le point est hors nœud : v_noeud est NULL)
    SELECT array_agg(m.id) INTO v_entrants
    FROM desimper.hydro_noeuds m
    WHERE m.ds = v_noeud
      AND ((m.entree IS NULL AND v_snap IS NOT NULL)                -- arrivée en tête
           OR m.entree IN (SELECT id FROM bv_amont_cel));           -- arrivée latérale

    -- 7. Union de couverture : partie fine + bassins amont reconstruits
    SELECT ST_SetSRID(ST_CoverageUnion(s.geo), g.srid) INTO v_res   -- ST_CoverageUnion perd le SRID
    FROM (
        SELECT ST_Segmentize(v_partiel, 1) AS geo
        UNION ALL
        SELECT e.geo
        FROM desimper.hydro_elements_amont(coalesce(v_entrants, '{}'::bigint[]), false) AS e(geo)
    ) s
    WHERE s.geo IS NOT NULL;

    DROP TABLE pg_temp.bv_cel;
    DROP TABLE pg_temp.bv_amont_cel;

    RETURN ST_Simplify(v_res, 0);   -- supprime les sommets alignés
END $$;


-- FUNCTION hydro_bassin_point(p_point geometry, p_rayon double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_point(p_point geometry, p_rayon double precision) IS 'Bassin versant d''un point, recalé sur le réseau dans le rayon p_rayon (m) : remontée fine cellule par cellule dans son bassin élémentaire, unie aux bassins amont reconstruits.';


-- hydro_bassin_polygone(geometry, double precision)
CREATE FUNCTION desimper.hydro_bassin_polygone(p_poly geometry, p_simplifier double precision DEFAULT 0) RETURNS geometry
    LANGUAGE plpgsql
    AS $$
DECLARE
    g       desimper.hydro_grille%ROWTYPE;
    r       record;
    v_parts geometry[] := '{}';
    v_ids   bigint[];
    v_geo   geometry;
    v_zone  geometry;
    v_fen   double precision := 1000;
    v_res   geometry;
    v_t     timestamptz := clock_timestamp();
BEGIN
    SELECT * INTO g FROM desimper.hydro_grille;
    IF ST_SRID(p_poly) <> g.srid THEN
        p_poly := ST_Transform(p_poly, g.srid);
    END IF;
    p_poly := ST_MakeValid(p_poly);

    -- 1. Cellules du polygone et leur cellule aval
    DROP TABLE IF EXISTS pg_temp.bp_cel;
    CREATE TEMP TABLE bp_cel AS
    SELECT px.id, px.lig, px.col,
           CASE WHEN c.code IS NOT NULL
                 AND px.col + c.dc BETWEEN 0 AND g.ncols - 1
                THEN px.id + c.dl * g.ncols + c.dc
           END AS down_id
    FROM desimper.hydro_d8_raster t
    CROSS JOIN LATERAL desimper.hydro_pixels(ST_Clip(t.rast, 1, p_poly, true)) px
    LEFT JOIN desimper.hydro_codes_d8 c ON c.code = px.val::int
    WHERE t.rast && p_poly
      AND ST_Intersects(ST_ConvexHull(t.rast), p_poly);
    CREATE INDEX ON bp_cel (id);
    RAISE NOTICE '[%] % cellules dans le polygone', clock_timestamp() - v_t, (SELECT count(*) FROM bp_cel);

    -- Polygone plus petit qu'une cellule, ou hors données : on se ramène à un point
    IF NOT EXISTS (SELECT 1 FROM bp_cel) THEN
        DROP TABLE pg_temp.bp_cel;
        v_res := ST_Union(p_poly, desimper.hydro_bassin_point(ST_PointOnSurface(p_poly), 0));
        RETURN CASE WHEN p_simplifier > 0
                    THEN ST_SimplifyPreserveTopology(v_res, p_simplifier) ELSE v_res END;
    END IF;

    -- 2. Exutoires : cellules dont l'aval sort du polygone, rattachées à leur nœud
    DROP TABLE IF EXISTS pg_temp.bp_exu;
    CREATE TEMP TABLE bp_exu AS
    SELECT e.id, n.id AS noeud,
           EXISTS (SELECT 1 FROM desimper.hydro_troncons t
                   WHERE t.id = n.id AND ST_DWithin(t.geom, e.pt, abs(g.sx) / 100)) AS sur_cours
    FROM (
        SELECT c.id,
               ST_SetSRID(ST_MakePoint(g.x0 + (c.col + 0.5) * g.sx,
                                       g.y0 + (c.lig + 0.5) * g.sy), g.srid) AS pt
        FROM bp_cel c
        WHERE c.down_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM bp_cel d WHERE d.id = c.down_id)
    ) e
    LEFT JOIN LATERAL (
        SELECT n.id FROM desimper.hydro_noeuds n WHERE ST_Intersects(n.geom, e.pt) LIMIT 1
    ) n ON true;

    RAISE NOTICE '[%] % exutoires, dont % hors nœud, répartis dans % bassins élémentaires',
        clock_timestamp() - v_t,
        (SELECT count(*) FROM bp_exu),
        (SELECT count(*) FROM bp_exu WHERE noeud IS NULL),
        (SELECT count(DISTINCT noeud) FROM bp_exu WHERE noeud IS NOT NULL);

    -- 3. Une remontée par bassin élémentaire, depuis tous ses exutoires
    FOR r IN
        SELECT x.noeud, array_agg(x.id) AS ids, bool_or(x.sur_cours) AS sur_cours, n.geom
        FROM bp_exu x JOIN desimper.hydro_noeuds n ON n.id = x.noeud
        GROUP BY x.noeud, n.geom
    LOOP
        v_parts := v_parts || desimper.hydro_remontee(r.geom, r.noeud, r.ids, r.sur_cours);
    END LOOP;

    -- 4. Exutoires hors nœud : fenêtre autour du projet, agrandie si besoin
    SELECT array_agg(id) INTO v_ids FROM bp_exu WHERE noeud IS NULL;
    IF v_ids IS NOT NULL THEN
        LOOP
            v_zone := ST_Expand(ST_Envelope(p_poly), v_fen);
            v_geo  := desimper.hydro_remontee(v_zone, NULL, v_ids, false);
            EXIT WHEN v_geo IS NULL
                   OR (ST_XMin(v_geo) > ST_XMin(v_zone) + abs(g.sx)
                   AND ST_XMax(v_geo) < ST_XMax(v_zone) - abs(g.sx)
                   AND ST_YMin(v_geo) > ST_YMin(v_zone) + abs(g.sx)
                   AND ST_YMax(v_geo) < ST_YMax(v_zone) - abs(g.sx));
            IF v_fen >= 4000 THEN
                RAISE NOTICE 'Bassin hors nœud plus grand que la fenêtre maximale : résultat tronqué';
                EXIT;
            END IF;
            v_fen := v_fen * 2;
        END LOOP;
        v_parts := v_parts || v_geo;
    END IF;

    DROP TABLE pg_temp.bp_cel;
    DROP TABLE pg_temp.bp_exu;
    RAISE NOTICE '[%] remontées terminées, union finale', clock_timestamp() - v_t;

    -- 5. Union des bassins (ils peuvent se recouvrir) et du projet lui-même
    v_res := ST_Union(ARRAY(
                 SELECT ST_SetSRID(x, g.srid)             -- SRID homogène, par sécurité
                 FROM unnest(array_append(array_remove(v_parts, NULL), p_poly)) AS x));
    v_res := ST_Simplify(v_res, 0);
    RAISE NOTICE '[%] terminé', clock_timestamp() - v_t;
    RETURN CASE WHEN p_simplifier > 0
                THEN ST_SimplifyPreserveTopology(v_res, p_simplifier) ELSE v_res END;
END $$;


-- FUNCTION hydro_bassin_polygone(p_poly geometry, p_simplifier double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_polygone(p_poly geometry, p_simplifier double precision) IS 'Bassin contributif d''un polygone de projet, polygone inclus : une remontée par bassin élémentaire, depuis tous les exutoires du polygone. Simplifié avec la tolérance p_simplifier (m).';


-- hydro_bassin_versant(geometry, double precision, double precision)
CREATE FUNCTION desimper.hydro_bassin_versant(p_points geometry, p_rayon double precision DEFAULT 0, p_simplifier double precision DEFAULT 0) RETURNS geometry
    LANGUAGE sql
    AS $$
    SELECT CASE WHEN p_simplifier > 0
                THEN ST_SimplifyPreserveTopology(u, p_simplifier)
                ELSE u END
    FROM (SELECT ST_Union(desimper.hydro_bassin_point(d.geom, p_rayon)) AS u
          FROM ST_Dump(p_points) d) s
$$;


-- FUNCTION hydro_bassin_versant(p_points geometry, p_rayon double precision, p_simplifier double precision)
COMMENT ON FUNCTION desimper.hydro_bassin_versant(p_points geometry, p_rayon double precision, p_simplifier double precision) IS 'Bassin versant unique d''un point ou d''un multipoint, simplifié avec la tolérance p_simplifier (m).';


-- hydro_bassins_par_point(geometry, double precision)
CREATE FUNCTION desimper.hydro_bassins_par_point(p_points geometry, p_rayon double precision DEFAULT 0) RETURNS TABLE(num integer, geom geometry)
    LANGUAGE sql
    AS $$
    SELECT coalesce(d.path[1], 1), desimper.hydro_bassin_point(d.geom, p_rayon)
    FROM ST_Dump(p_points) d
$$;


-- FUNCTION hydro_bassins_par_point(p_points geometry, p_rayon double precision)
COMMENT ON FUNCTION desimper.hydro_bassins_par_point(p_points geometry, p_rayon double precision) IS 'Un bassin versant par point d''un multipoint.';


-- hydro_elements_amont(bigint[], boolean)
CREATE FUNCTION desimper.hydro_elements_amont(p_departs bigint[], p_ouvrir boolean) RETURNS SETOF geometry
    LANGUAGE sql STABLE
    AS $$
    WITH RECURSIVE amont(id, arret) AS (
        SELECT n.id, (n.precalc AND NOT p_ouvrir)
        FROM desimper.hydro_noeuds n
        WHERE n.id = ANY (p_departs)
        UNION
        SELECT m.id, m.precalc
        FROM desimper.hydro_noeuds m
        JOIN amont a ON m.ds = a.id
        WHERE NOT a.arret
    )
    SELECT CASE WHEN a.arret THEN b.geom ELSE n.geom END
    FROM amont a
    JOIN desimper.hydro_noeuds n ON n.id = a.id
    LEFT JOIN desimper.hydro_bv_amont b ON b.id = a.id
$$;


-- FUNCTION hydro_elements_amont(p_departs bigint[], p_ouvrir boolean)
COMMENT ON FUNCTION desimper.hydro_elements_amont(p_departs bigint[], p_ouvrir boolean) IS 'Morceaux du bassin amont d''un ensemble de nœuds : polygone élémentaire des nœuds non précalculés, bassin amont stocké des nœuds précalculés (où la remontée s''arrête). p_ouvrir = true développe toujours les nœuds de départ.';


-- hydro_fleches_ecoulement(geometry, double precision)
CREATE FUNCTION desimper.hydro_fleches_ecoulement(p_poly geometry, p_pas double precision DEFAULT 5) RETURNS TABLE(geom geometry, angle double precision, coherence double precision, nb_cellules integer)
    LANGUAGE sql STABLE
    AS $$
    WITH g AS (
        SELECT gr.*, greatest(1, round(p_pas / abs(gr.sx)))::int AS k FROM desimper.hydro_grille gr
    ), z AS (
        SELECT CASE WHEN ST_SRID(p_poly) = g.srid THEN p_poly
                    ELSE ST_Transform(p_poly, g.srid) END AS poly
        FROM g
    ), cel AS (
        SELECT px.lig, px.col,
               c.dc / sqrt(c.dl^2 + c.dc^2)  AS vx,     -- vers l'est
               -c.dl / sqrt(c.dl^2 + c.dc^2) AS vy      -- vers le nord
        FROM z
        CROSS JOIN desimper.hydro_d8_raster t
        CROSS JOIN LATERAL desimper.hydro_pixels(ST_Clip(t.rast, 1, z.poly, true)) px
        JOIN desimper.hydro_codes_d8 c ON c.code = px.val::int
        WHERE t.rast && z.poly
          AND ST_Intersects(ST_ConvexHull(t.rast), z.poly)
    ), m AS (
        SELECT cel.lig / g.k AS bl, cel.col / g.k AS bc,
               sum(cel.vx) AS ux, sum(cel.vy) AS uy, count(*) AS n
        FROM cel CROSS JOIN g
        GROUP BY 1, 2
    )
    SELECT ST_SetSRID(ST_MakePoint(g.x0 + (m.bc + 0.5) * g.k * g.sx,
                                   g.y0 + (m.bl + 0.5) * g.k * g.sy), g.srid),
           mod((degrees(atan2(m.ux, m.uy)) + 360)::numeric, 360)::double precision,
           sqrt(m.ux ^ 2 + m.uy ^ 2) / m.n,
           m.n::int
    FROM m CROSS JOIN g
    WHERE m.n >= g.k * g.k / 4.0            -- ignore les mailles à peine entamées
$$;


-- FUNCTION hydro_fleches_ecoulement(p_poly geometry, p_pas double precision)
COMMENT ON FUNCTION desimper.hydro_fleches_ecoulement(p_poly geometry, p_pas double precision) IS 'Flèches d''écoulement d''un polygone : direction moyenne de l''écoulement D8 (angle en degrés depuis le nord, sens horaire) et cohérence des directions, par maille de p_pas mètres.';


-- hydro_lignes_ecoulement(geometry, double precision, double precision)
CREATE FUNCTION desimper.hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision DEFAULT 10, p_marge double precision DEFAULT 50) RETURNS TABLE(depart bigint, geom geometry, longueur double precision)
    LANGUAGE sql STABLE
    AS $$
    WITH RECURSIVE g AS (
        SELECT gr.*, greatest(1, round(p_espacement / abs(gr.sx)))::int AS k FROM desimper.hydro_grille gr
    ), z AS (
        SELECT CASE WHEN ST_SRID(p_poly) = g.srid THEN p_poly
                    ELSE ST_Transform(p_poly, g.srid) END AS poly
        FROM g
    ), zone AS (
        SELECT z.poly, ST_Buffer(z.poly, p_marge) AS zp FROM z
    ), cel AS (
        SELECT px.id, px.lig, px.col,
               CASE WHEN c.code IS NOT NULL
                     AND px.col + c.dc BETWEEN 0 AND g.ncols - 1
                    THEN px.id + c.dl * g.ncols + c.dc
               END AS down_id,
               ST_Intersects(zone.poly,
                   ST_SetSRID(ST_MakePoint(g.x0 + (px.col + 0.5) * g.sx,
                                           g.y0 + (px.lig + 0.5) * g.sy), g.srid)) AS dedans
        FROM zone
        CROSS JOIN g
        CROSS JOIN desimper.hydro_d8_raster t
        CROSS JOIN LATERAL desimper.hydro_pixels(ST_Clip(t.rast, 1, zone.zp, true)) px
        LEFT JOIN desimper.hydro_codes_d8 c ON c.code = px.val::int
        WHERE t.rast && zone.zp
          AND ST_Intersects(ST_ConvexHull(t.rast), zone.zp)
    ), germes AS (
        SELECT cel.id FROM cel CROSS JOIN g
        WHERE cel.dedans AND cel.lig % g.k = 0 AND cel.col % g.k = 0
    ), chemin(depart, id, etape) AS (
        SELECT id, id, 0 FROM germes
        UNION ALL
        SELECT ch.depart, c.down_id, ch.etape + 1
        FROM chemin ch JOIN cel c ON c.id = ch.id     -- s'arrête en sortant de la zone
        WHERE c.down_id IS NOT NULL AND ch.etape < 20000
    ), pts AS (
        SELECT ch.depart, ch.etape,
               ST_SetSRID(ST_MakePoint(g.x0 + ((ch.id % g.ncols) + 0.5) * g.sx,
                                       g.y0 + ((ch.id / g.ncols) + 0.5) * g.sy), g.srid) AS pt
        FROM chemin ch CROSS JOIN g
    )
    SELECT depart, l, ST_Length(l)
    FROM (SELECT depart, ST_MakeLine(pt ORDER BY etape) AS l
          FROM pts GROUP BY depart HAVING count(*) > 1) s
$$;


-- FUNCTION hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision, p_marge double precision)
COMMENT ON FUNCTION desimper.hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision, p_marge double precision) IS 'Lignes d''écoulement tracées de cellule en cellule depuis des départs espacés de p_espacement mètres dans le polygone, jusqu''à la sortie du polygone élargi de p_marge mètres.';


-- hydro_pixels(raster)
CREATE FUNCTION desimper.hydro_pixels(r raster) RETURNS TABLE(id bigint, lig integer, col integer, val double precision)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    g      desimper.hydro_grille%ROWTYPE;
    v_lig0 int;
    v_col0 int;
BEGIN
    IF r IS NULL THEN
        RETURN;
    END IF;
    SELECT * INTO g FROM desimper.hydro_grille;
    v_lig0 := round((ST_UpperLeftY(r) - g.y0) / g.sy);
    v_col0 := round((ST_UpperLeftX(r) - g.x0) / g.sx);
    RETURN QUERY
    SELECT (v_lig0 + p.y - 1)::bigint * g.ncols + (v_col0 + p.x - 1),
           v_lig0 + p.y - 1,
           v_col0 + p.x - 1,
           p.val
    FROM ST_PixelAsCentroids(r, 1, true) p;
END $$;


-- FUNCTION hydro_pixels(r raster)
COMMENT ON FUNCTION desimper.hydro_pixels(r raster) IS 'Pixels d''une tuile (ou d''un extrait de tuile) du raster D8, avec leur identifiant global de cellule (lig * ncols + col), leur ligne, leur colonne et leur valeur.';


-- hydro_remontee(geometry, bigint, bigint[], boolean)
CREATE FUNCTION desimper.hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean) RETURNS geometry
    LANGUAGE plpgsql
    SET enable_hashjoin TO 'off'
    SET enable_mergejoin TO 'off'
    AS $$
DECLARE
    g          desimper.hydro_grille%ROWTYPE;
    v_partiel  geometry;
    v_entrants bigint[];
    v_res      geometry;
    v_t        timestamptz := clock_timestamp();
    v_n        bigint;
BEGIN
    SELECT * INTO g FROM desimper.hydro_grille;
    RAISE NOTICE '  remontée : nœud %, % départs, zone de % km²',
        coalesce(p_noeud::text, 'aucun (fenêtre)'), cardinality(p_departs),
        round((ST_Area(p_zone) / 1e6)::numeric, 2);

    DROP TABLE IF EXISTS pg_temp.rm_cel;
    CREATE TEMP TABLE rm_cel AS
    SELECT px.id,
           CASE WHEN c.code IS NOT NULL
                 AND px.col + c.dc BETWEEN 0 AND g.ncols - 1
                THEN px.id + c.dl * g.ncols + c.dc
           END AS down_id
    FROM desimper.hydro_d8_raster t
    CROSS JOIN LATERAL desimper.hydro_pixels(ST_Clip(t.rast, 1, p_zone, true)) px
    LEFT JOIN desimper.hydro_codes_d8 c ON c.code = px.val::int
    WHERE t.rast && p_zone
      AND ST_Intersects(ST_ConvexHull(t.rast), p_zone);
    CREATE INDEX ON rm_cel (down_id);
    ANALYZE rm_cel;
    SELECT count(*) INTO v_n FROM rm_cel;
    RAISE NOTICE '  [%] % cellules lues', clock_timestamp() - v_t, v_n;

    DROP TABLE IF EXISTS pg_temp.rm_amont;
    CREATE TEMP TABLE rm_amont AS
    WITH RECURSIVE amont(id) AS (
        SELECT unnest(p_departs)
        UNION
        SELECT c.id FROM rm_cel c JOIN amont a ON c.down_id = a.id
    )
    SELECT id FROM amont;
    CREATE INDEX ON rm_amont (id);
    SELECT count(*) INTO v_n FROM rm_amont;
    RAISE NOTICE '  [%] % cellules en amont', clock_timestamp() - v_t, v_n;

    WITH cel AS (
        SELECT (id / g.ncols)::int AS lig, (id % g.ncols)::int AS col FROM rm_amont
    ), segments AS (
        SELECT lig, min(col) AS c1, max(col) AS c2
        FROM (SELECT lig, col,
                     col - row_number() OVER (PARTITION BY lig ORDER BY col) AS grp
              FROM cel) s
        GROUP BY lig, grp
    )
    SELECT ST_Union(ST_MakeEnvelope(
               g.x0 + c1 * g.sx,       g.y0 + (lig + 1) * g.sy,
               g.x0 + (c2 + 1) * g.sx, g.y0 + lig * g.sy,
               g.srid))
    INTO v_partiel
    FROM segments;
    RAISE NOTICE '  [%] partie fine vectorisée (% sommets)', clock_timestamp() - v_t, ST_NPoints(v_partiel);

    IF p_noeud IS NOT NULL THEN
        SELECT array_agg(m.id) INTO v_entrants
        FROM desimper.hydro_noeuds m
        WHERE m.ds = p_noeud
          AND ((m.entree IS NULL AND p_sur_cours)
               OR m.entree IN (SELECT id FROM rm_amont));
    END IF;
    RAISE NOTICE '  [%] % nœuds amont à ajouter', clock_timestamp() - v_t, coalesce(cardinality(v_entrants), 0);

    SELECT ST_SetSRID(ST_CoverageUnion(s.geo), g.srid) INTO v_res   -- ST_CoverageUnion perd le SRID
    FROM (
        SELECT ST_Segmentize(v_partiel, 1) AS geo
        UNION ALL
        SELECT e.geo
        FROM desimper.hydro_elements_amont(coalesce(v_entrants, '{}'::bigint[]), false) AS e(geo)
    ) s
    WHERE s.geo IS NOT NULL;

    RAISE NOTICE '  [%] union terminée (% sommets)', clock_timestamp() - v_t, ST_NPoints(v_res);

    DROP TABLE pg_temp.rm_cel;
    DROP TABLE pg_temp.rm_amont;
    RETURN v_res;
END $$;


-- FUNCTION hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean)
COMMENT ON FUNCTION desimper.hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean) IS 'Remontée multi-départs dans une zone (un nœud, ou une fenêtre hors nœud), unie aux bassins amont des nœuds qui s''y jettent.';


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



