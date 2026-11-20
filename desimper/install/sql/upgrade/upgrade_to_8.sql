BEGIN;

-- Hydrological tables and functions (prefixed by hydro_) used to compute the
-- project watersheds and flows. The data (D8 directions, graph of the elementary
-- watersheds, precomputed upstream watersheds) are produced apart from the plugin,
-- with TauDEM: only the structure and the production functions are installed here.

CREATE EXTENSION IF NOT EXISTS postgis_raster;


-- Grid of the D8 raster: one row
CREATE TABLE desimper.hydro_grille (
    x0 double precision,
    y0 double precision,
    sx double precision,
    sy double precision,
    srid integer,
    ncols integer
);

COMMENT ON TABLE desimper.hydro_grille IS 'Grille du raster des directions D8 (une seule ligne). Une cellule a pour identifiant global lig * ncols + col. Ne doit jamais être recalculée en production : les identifiants de cellule stockés dans hydro_noeuds en dépendent.';
COMMENT ON COLUMN desimper.hydro_grille.x0 IS 'Abscisse du coin supérieur gauche de la grille.';
COMMENT ON COLUMN desimper.hydro_grille.y0 IS 'Ordonnée du coin supérieur gauche de la grille.';
COMMENT ON COLUMN desimper.hydro_grille.sx IS 'Taille d''une cellule en X (m).';
COMMENT ON COLUMN desimper.hydro_grille.sy IS 'Taille d''une cellule en Y (m), négative.';
COMMENT ON COLUMN desimper.hydro_grille.srid IS 'Système de coordonnées de la grille.';
COMMENT ON COLUMN desimper.hydro_grille.ncols IS 'Nombre de colonnes de la grille.';


-- TauDEM D8 coding
CREATE TABLE desimper.hydro_codes_d8 (
    code integer PRIMARY KEY,
    dl integer,
    dc integer
);

INSERT INTO desimper.hydro_codes_d8 (code, dl, dc) VALUES
    (1, 0, 1),
    (2, -1, 1),
    (3, -1, 0),
    (4, -1, -1),
    (5, 0, -1),
    (6, 1, -1),
    (7, 1, 0),
    (8, 1, 1);

COMMENT ON TABLE desimper.hydro_codes_d8 IS 'Codage des directions D8 de TauDEM : 1 = est, puis sens antihoraire jusqu''à 8 = sud-est.';
COMMENT ON COLUMN desimper.hydro_codes_d8.code IS 'Code de direction D8 de TauDEM.';
COMMENT ON COLUMN desimper.hydro_codes_d8.dl IS 'Décalage en ligne vers la cellule aval (positif vers le bas).';
COMMENT ON COLUMN desimper.hydro_codes_d8.dc IS 'Décalage en colonne vers la cellule aval (positif vers la droite).';


-- D8 flow directions at 1 m, loaded with raster2pgsql -a
CREATE TABLE desimper.hydro_d8_raster (
    rid serial PRIMARY KEY,
    rast raster
);

CREATE INDEX hydro_d8_raster_st_convexhull_idx ON desimper.hydro_d8_raster USING gist (ST_ConvexHull(rast));

COMMENT ON TABLE desimper.hydro_d8_raster IS 'Directions d''écoulement D8 à 1 m (codes TauDEM), en tuiles. Chargées avec raster2pgsql -a.';
COMMENT ON COLUMN desimper.hydro_d8_raster.rid IS 'Identifiant de la tuile.';
COMMENT ON COLUMN desimper.hydro_d8_raster.rast IS 'Tuile du raster des directions D8.';


-- Nodes of the hydrographic graph: one per elementary watershed
CREATE TABLE desimper.hydro_noeuds (
    id bigint PRIMARY KEY,
    piece integer,
    ds bigint,
    entree bigint,
    resolu boolean DEFAULT false,
    geom geometry(MultiPolygon, 2154),
    surf double precision,
    surf_amont double precision,
    precalc boolean DEFAULT false
);

CREATE INDEX hydro_noeuds_geom_idx ON desimper.hydro_noeuds USING gist (geom);
CREATE INDEX hydro_noeuds_ds_idx ON desimper.hydro_noeuds USING btree (ds);

COMMENT ON TABLE desimper.hydro_noeuds IS 'Nœuds du graphe hydrographique : un nœud par bassin élémentaire, relié à son nœud aval.';
COMMENT ON COLUMN desimper.hydro_noeuds.id IS 'Identifiant du nœud : morceau * 1 000 000 + numéro TauDEM du bassin (WSNO).';
COMMENT ON COLUMN desimper.hydro_noeuds.piece IS 'Morceau de calcul TauDEM d''origine.';
COMMENT ON COLUMN desimper.hydro_noeuds.ds IS 'Nœud aval (NULL à l''exutoire).';
COMMENT ON COLUMN desimper.hydro_noeuds.entree IS 'Cellule d''entrée dans le nœud aval quand l''eau traverse une limite de morceau (NULL si le nœud arrive en tête du tronçon aval).';
COMMENT ON COLUMN desimper.hydro_noeuds.resolu IS 'Nœud aval recherché (utilisé pendant la préparation).';
COMMENT ON COLUMN desimper.hydro_noeuds.geom IS 'Polygone du bassin élémentaire, densifié avec un sommet par mètre.';
COMMENT ON COLUMN desimper.hydro_noeuds.surf IS 'Surface du bassin élémentaire (m²).';
COMMENT ON COLUMN desimper.hydro_noeuds.surf_amont IS 'Surface drainée par le nœud, bassins amont compris (m²).';
COMMENT ON COLUMN desimper.hydro_noeuds.precalc IS 'Bassin amont précalculé dans hydro_bv_amont.';


-- Stream reaches, used to snap the points on the network
CREATE TABLE desimper.hydro_troncons (
    id bigint,
    piece integer,
    linkno integer,
    dslinkno integer,
    geom geometry(MultiLineString, 2154)
);

CREATE INDEX hydro_troncons_id_idx ON desimper.hydro_troncons USING btree (id);
CREATE INDEX hydro_troncons_geom_idx ON desimper.hydro_troncons USING gist (geom);

COMMENT ON TABLE desimper.hydro_troncons IS 'Tronçons du réseau hydrographique TauDEM, utilisés pour recaler les points sur les cours d''eau.';
COMMENT ON COLUMN desimper.hydro_troncons.id IS 'Nœud (bassin élémentaire) du tronçon.';
COMMENT ON COLUMN desimper.hydro_troncons.piece IS 'Morceau de calcul TauDEM d''origine.';
COMMENT ON COLUMN desimper.hydro_troncons.linkno IS 'Numéro TauDEM du tronçon dans son morceau.';
COMMENT ON COLUMN desimper.hydro_troncons.dslinkno IS 'Numéro TauDEM du tronçon aval dans le même morceau.';
COMMENT ON COLUMN desimper.hydro_troncons.geom IS 'Tracé du tronçon.';


-- Precomputed upstream watersheds of the main nodes
CREATE TABLE desimper.hydro_bv_amont (
    id bigint PRIMARY KEY,
    geom geometry(Geometry, 2154)
);

CREATE INDEX hydro_bv_amont_geom_idx ON desimper.hydro_bv_amont USING gist (geom);

COMMENT ON TABLE desimper.hydro_bv_amont IS 'Bassins amont précalculés des nœuds qui drainent une grande surface (hydro_noeuds.precalc).';
COMMENT ON COLUMN desimper.hydro_bv_amont.id IS 'Nœud dont c''est le bassin amont.';
COMMENT ON COLUMN desimper.hydro_bv_amont.geom IS 'Bassin amont complet du nœud.';

-- Production functions

CREATE OR REPLACE FUNCTION desimper.hydro_pixels(r raster)
 RETURNS TABLE(id bigint, lig integer, col integer, val double precision)
 LANGUAGE plpgsql
 STABLE
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
END $$
;


CREATE OR REPLACE FUNCTION desimper.hydro_elements_amont(p_departs bigint[], p_ouvrir boolean)
 RETURNS SETOF geometry
 LANGUAGE sql
 STABLE
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
$$
;


CREATE OR REPLACE FUNCTION desimper.hydro_bassin_point(p_point geometry, p_rayon double precision DEFAULT 0)
 RETURNS geometry
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
END $$
;


CREATE OR REPLACE FUNCTION desimper.hydro_bassin_versant(p_points geometry, p_rayon double precision DEFAULT 0, p_simplifier double precision DEFAULT 0)
 RETURNS geometry
 LANGUAGE sql
AS $$
    SELECT CASE WHEN p_simplifier > 0
                THEN ST_SimplifyPreserveTopology(u, p_simplifier)
                ELSE u END
    FROM (SELECT ST_Union(desimper.hydro_bassin_point(d.geom, p_rayon)) AS u
          FROM ST_Dump(p_points) d) s
$$
;


CREATE OR REPLACE FUNCTION desimper.hydro_bassins_par_point(p_points geometry, p_rayon double precision DEFAULT 0)
 RETURNS TABLE(num integer, geom geometry)
 LANGUAGE sql
AS $$
    SELECT coalesce(d.path[1], 1), desimper.hydro_bassin_point(d.geom, p_rayon)
    FROM ST_Dump(p_points) d
$$
;


CREATE OR REPLACE FUNCTION desimper.hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean)
 RETURNS geometry
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
END $$
;


CREATE OR REPLACE FUNCTION desimper.hydro_bassin_polygone(p_poly geometry, p_simplifier double precision DEFAULT 0)
 RETURNS geometry
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
END $$
;


CREATE OR REPLACE FUNCTION desimper.hydro_fleches_ecoulement(p_poly geometry, p_pas double precision DEFAULT 5)
 RETURNS TABLE(geom geometry, angle double precision, coherence double precision, nb_cellules integer)
 LANGUAGE sql
 STABLE
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
$$
;


CREATE OR REPLACE FUNCTION desimper.hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision DEFAULT 10, p_marge double precision DEFAULT 50)
 RETURNS TABLE(depart bigint, geom geometry, longueur double precision)
 LANGUAGE sql
 STABLE
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
$$
;

COMMENT ON FUNCTION desimper.hydro_pixels(r raster) IS 'Pixels d''une tuile (ou d''un extrait de tuile) du raster D8, avec leur identifiant global de cellule (lig * ncols + col), leur ligne, leur colonne et leur valeur.';

COMMENT ON FUNCTION desimper.hydro_elements_amont(p_departs bigint[], p_ouvrir boolean) IS 'Morceaux du bassin amont d''un ensemble de nœuds : polygone élémentaire des nœuds non précalculés, bassin amont stocké des nœuds précalculés (où la remontée s''arrête). p_ouvrir = true développe toujours les nœuds de départ.';

COMMENT ON FUNCTION desimper.hydro_bassin_point(p_point geometry, p_rayon double precision) IS 'Bassin versant d''un point, recalé sur le réseau dans le rayon p_rayon (m) : remontée fine cellule par cellule dans son bassin élémentaire, unie aux bassins amont reconstruits.';

COMMENT ON FUNCTION desimper.hydro_bassin_versant(p_points geometry, p_rayon double precision, p_simplifier double precision) IS 'Bassin versant unique d''un point ou d''un multipoint, simplifié avec la tolérance p_simplifier (m).';

COMMENT ON FUNCTION desimper.hydro_bassins_par_point(p_points geometry, p_rayon double precision) IS 'Un bassin versant par point d''un multipoint.';

COMMENT ON FUNCTION desimper.hydro_remontee(p_zone geometry, p_noeud bigint, p_departs bigint[], p_sur_cours boolean) IS 'Remontée multi-départs dans une zone (un nœud, ou une fenêtre hors nœud), unie aux bassins amont des nœuds qui s''y jettent.';

COMMENT ON FUNCTION desimper.hydro_bassin_polygone(p_poly geometry, p_simplifier double precision) IS 'Bassin contributif d''un polygone de projet, polygone inclus : une remontée par bassin élémentaire, depuis tous les exutoires du polygone. Simplifié avec la tolérance p_simplifier (m).';

COMMENT ON FUNCTION desimper.hydro_fleches_ecoulement(p_poly geometry, p_pas double precision) IS 'Flèches d''écoulement d''un polygone : direction moyenne de l''écoulement D8 (angle en degrés depuis le nord, sens horaire) et cohérence des directions, par maille de p_pas mètres.';

COMMENT ON FUNCTION desimper.hydro_lignes_ecoulement(p_poly geometry, p_espacement double precision, p_marge double precision) IS 'Lignes d''écoulement tracées de cellule en cellule depuis des départs espacés de p_espacement mètres dans le polygone, jusqu''à la sortie du polygone élargi de p_marge mètres.';


-- The project functions now use the hydrological functions of the plugin
CREATE OR REPLACE FUNCTION desimper.calculer_bassin_versant(id_projet integer) RETURNS json
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

COMMENT ON FUNCTION desimper.calculer_bassin_versant(id_projet integer) IS 'Calcule (ou recalcule) le bassin versant automatique d''un projet avec desimper.hydro_bassin_polygone() et l''enregistre dans bassins_versants avec corrige = false.
Le bassin versant corrigé par l''utilisateur n''est pas modifié.
Renvoie le bassin versant en GeoJSON (FeatureCollection).';


CREATE OR REPLACE FUNCTION desimper.calculer_ecoulements(
    id_projet integer,
    pas_fleches double precision DEFAULT 5,
    espacement_lignes double precision DEFAULT 10,
    marge_lignes double precision DEFAULT 50
) RETURNS json
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

COMMENT ON FUNCTION desimper.calculer_ecoulements(id_projet integer, pas_fleches double precision, espacement_lignes double precision, marge_lignes double precision) IS 'Calcule (ou recalcule) les flèches et les lignes d''écoulement d''un projet avec desimper.hydro_fleches_ecoulement() et desimper.hydro_lignes_ecoulement(), et les enregistre dans fleches_ecoulement et lignes_ecoulement.
Paramètres : taille des mailles des flèches (m), espacement des départs des lignes (m), prolongement des lignes au-delà du projet (m).
Renvoie le nombre de flèches et de lignes enregistrées.';

COMMENT ON TABLE desimper.fleches_ecoulement IS 'Flèches d''écoulement des projets : une flèche par maille, orientée selon la direction moyenne de l''écoulement D8 des cellules de la maille. Calculées avec desimper.hydro_fleches_ecoulement().';

COMMENT ON TABLE desimper.lignes_ecoulement IS 'Lignes d''écoulement des projets : tracées de cellule en cellule selon les directions D8, depuis des points de départ régulièrement espacés, et prolongées au-delà du projet. Calculées avec desimper.hydro_lignes_ecoulement().';

COMMIT;
