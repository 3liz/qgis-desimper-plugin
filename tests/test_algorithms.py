"""Tests the algorithms & the SQL functions of the plugin."""

from decimal import Decimal
from typing import Any

import psycopg
import pytest

from qgis import processing
from qgis.core import QgsVectorLayer

from desimper.plugin_tools.feedback import LoggerProcessingFeedBack
from desimper.processing.provider import Provider


def test_import_context(
    connected_database: None,
    initialized_database: psycopg.Connection,
    context_layer: QgsVectorLayer,
    processing_provider: Provider,
    imported_context: dict[str, Any],
):
    """Import a context layer into the target table of an existing context."""
    # Algorithm is working
    assert imported_context["OUTPUT_STATUS"] == 1
    assert imported_context["OUTPUT_STRING"] == (
        "Context layer has been imported successfully into the database."
    )

    # Data has been imported
    cursor = initialized_database.cursor()
    cursor.execute(
        """
        SELECT unique_object_id, fk_code_liste_contextes, libelle, valeur
        FROM desimper.contexte_baignade
        WHERE fk_code_liste_contextes = 'BAI'
        ORDER BY unique_object_id
        LIMIT 1
        """
    )

    records = cursor.fetchall()
    result = records[0]
    assert result[0] == "1"
    assert result[1] == "BAI"
    assert result[2] == "Pas de site de baignade"
    assert result[3] == "0"

    # View has been created
    cursor.execute(
        """
        SELECT COUNT(*) FROM desimper.v_contexte_baignade
        """
    )
    records = cursor.fetchall()
    result = records[0][0]
    assert result > 0

    # Overide is working
    params = {
        "CONNECTION_NAME": "test",
        "TARGET_CONTEXT": 0,  # 0 = Baignade
        "OVERRIDE": True,
        "CONTEXT_LAYER": context_layer,
        "LABEL_FIELD": "label",
        "VALUE_FIELD": "value",
        "UNIQUE_ID_FIELD": "id",
    }
    feedback = LoggerProcessingFeedBack()
    alg = f"{processing_provider.id()}:import_context_data"
    processing_output = processing.run(alg, params, feedback=feedback)
    assert processing_output["OUTPUT_STATUS"] == 1

    cursor.execute(
        """
        SELECT COUNT(*) FROM desimper.contexte_baignade
        """
    )
    records = cursor.fetchall()
    result = records[0][0]
    assert result == 6  # 5 features, but 1 is subdivised


def test_fill_contextes_projets(
    initialized_database: psycopg.Connection,
    imported_context: dict[str, Any],
):
    """Fill the contextes_projets table with the contexts intersecting a project."""
    assert imported_context["OUTPUT_STATUS"] == 1

    cursor = initialized_database.cursor()

    # Unknown project is rejected
    cursor.execute("SELECT desimper.fill_contextes_projets(-1)")
    record = cursor.fetchone()
    assert record is not None
    result = record[0]
    assert result["status"] == "error"
    assert result["message"] == "Le projet passé en paramètre n'existe pas"

    # The contexts intersecting the project are inserted
    cursor.execute("SELECT desimper.fill_contextes_projets(1)")
    record = cursor.fetchone()
    assert record is not None
    result = record[0]
    assert result["status"] == "success"
    assert result["contexts_intersected"] == 1
    assert result["rows_inserted"] > 0

    # The right contexts intersecting the project are inserted
    cursor.execute("""
        SELECT id, fk_id_projet, surface_m, code_contexte, id_objet_contexte
        FROM desimper.contextes_projets
        ORDER BY id
    """)
    assert cursor.fetchone() == (1, 1, Decimal("2500.00"), "BAI", 1)
    assert cursor.fetchone() == (2, 1, Decimal("10000.00"), "BAI", 4)

    # Running the function again does not duplicate the rows
    cursor.execute("SELECT desimper.fill_contextes_projets(1)")
    record = cursor.fetchone()
    assert record is not None
    assert record[0]["rows_inserted"] == 2

    # A project without any intersecting context inserts nothing
    cursor.execute("SELECT desimper.fill_contextes_projets(2)")
    record = cursor.fetchone()
    assert record is not None
    result = record[0]
    assert result["status"] == "success"
    assert result["rows_inserted"] == 0
    assert result["contexts_intersected"] == 0


# Synthetic hydrological data: a 500 x 500 m D8 raster at 1 m, from (-150, -150)
# to (350, 350), where every cell flows to the east (TauDEM code 1), split into
# 4 tiles, and a single elementary watershed covering the whole raster.
HYDRO_DATA_SQL = """
    INSERT INTO desimper.hydro_grille (x0, y0, sx, sy, srid, ncols)
    VALUES (-150, 350, 1, -1, 2154, 500);

    INSERT INTO desimper.hydro_d8_raster (rast)
    SELECT ST_Tile(
        ST_AddBand(
            ST_MakeEmptyRaster(500, 500, -150, 350, 1, -1, 0, 0, 2154),
            '16BSI'::text, 1, -32768
        ),
        250, 250
    );

    INSERT INTO desimper.hydro_noeuds (id, piece, geom, precalc)
    VALUES (1, 1, ST_Multi(ST_MakeEnvelope(-150, -150, 350, 350, 2154)), false);
"""

HYDRO_TABLES = "desimper.hydro_grille, desimper.hydro_d8_raster, desimper.hydro_noeuds"


def load_hydro_data(cursor: psycopg.Cursor):
    """Load the synthetic hydrological data"""
    cursor.execute(HYDRO_DATA_SQL)


def test_bassins_versants(initialized_database: psycopg.Connection):
    """Compute, correct and invalidate the watersheds of a project."""
    cursor = initialized_database.cursor()

    def bassins_versants() -> list[tuple[int, bool]]:
        cursor.execute("""
            SELECT id, corrige
            FROM desimper.bassins_versants
            WHERE fk_id_projet = 1
            ORDER BY corrige
        """)
        return cursor.fetchall()

    def check_bassin_automatique(xmax: int, ymax: int):
        """Everything flows to the east: the automatic watershed of a project (0 0, xmax ymax)
        is the band of the project rows, from the west edge of the data to the project.
        The cells on the south and east edges of the project may be included by ST_Clip,
        as the project is aligned on the grid.
        """
        cursor.execute(
            """
            SELECT
                ST_Covers(geom, ST_MakeEnvelope(-150, 0, %(xmax)s, %(ymax)s, 2154)),
                ST_Covers(ST_MakeEnvelope(-150, -1, %(xmax)s + 1, %(ymax)s, 2154), geom)
            FROM desimper.bassins_versants
            WHERE fk_id_projet = 1 AND NOT corrige
            """,
            {"xmax": xmax, "ymax": ymax},
        )
        assert cursor.fetchone() == (True, True)

    # The hydrological data are not loaded
    with pytest.raises(psycopg.errors.RaiseException, match="ne sont pas chargées"):
        cursor.execute("SELECT desimper.calculer_bassin_versant(1)")

    # No automatic watershed to correct
    with pytest.raises(psycopg.errors.RaiseException, match="pas de bassin versant"):
        cursor.execute("SELECT desimper.creer_bassin_versant_corrige(1)")

    load_hydro_data(cursor)
    try:
        # Unknown project
        with pytest.raises(psycopg.errors.RaiseException, match="n'existe pas"):
            cursor.execute("SELECT desimper.calculer_bassin_versant(-1)")

        # The automatic watershed is created
        cursor.execute("SELECT desimper.calculer_bassin_versant(1)")
        record = cursor.fetchone()
        assert record is not None
        result = record[0]
        assert result["type"] == "FeatureCollection"
        assert result["features"][0]["geometry"]["type"] == "MultiPolygon"
        auto = bassins_versants()
        assert len(auto) == 1
        assert auto[0][1] is False

        check_bassin_automatique(100, 100)

        # Computing again updates the same row
        cursor.execute("SELECT desimper.calculer_bassin_versant(1)")
        assert bassins_versants() == auto

        # The corrected watershed is a copy of the automatic one
        cursor.execute("SELECT desimper.creer_bassin_versant_corrige(1)")
        record = cursor.fetchone()
        assert record is not None
        corrected_id = record[0]
        assert bassins_versants() == [auto[0], (corrected_id, True)]
        cursor.execute("""
            SELECT ST_Equals(a.geom, c.geom)
            FROM desimper.bassins_versants AS a, desimper.bassins_versants AS c
            WHERE a.fk_id_projet = 1 AND NOT a.corrige
            AND c.fk_id_projet = 1 AND c.corrige
        """)
        assert cursor.fetchone() == (True,)

        # Creating it again returns the existing one
        cursor.execute("SELECT desimper.creer_bassin_versant_corrige(1)")
        assert cursor.fetchone() == (corrected_id,)

        # Changing the project geometry removes the automatic watershed only
        cursor.execute("""
            UPDATE desimper.projets
            SET geom = ST_Multi(ST_GeomFromText('POLYGON((0 0, 0 200, 200 200, 200 0, 0 0))', 2154))
            WHERE id = 1
        """)
        assert bassins_versants() == [(corrected_id, True)]

        # Recomputing does not touch the corrected watershed
        cursor.execute("SELECT desimper.calculer_bassin_versant(1)")
        result = bassins_versants()
        assert len(result) == 2
        assert result[1] == (corrected_id, True)
        check_bassin_automatique(200, 200)

        # Deleting the project deletes its watersheds
        cursor.execute("DELETE FROM desimper.projets WHERE id = 1")
        assert bassins_versants() == []
    finally:
        cursor.execute(f"TRUNCATE {HYDRO_TABLES}")


def test_ecoulements(initialized_database: psycopg.Connection):
    """Compute and invalidate the flow arrows and flow lines of a project."""
    cursor = initialized_database.cursor()

    def counts() -> tuple[int, int]:
        cursor.execute("""
            SELECT
                (SELECT count(*) FROM desimper.fleches_ecoulement WHERE fk_id_projet = 1),
                (SELECT count(*) FROM desimper.lignes_ecoulement WHERE fk_id_projet = 1)
        """)
        record = cursor.fetchone()
        assert record is not None
        return record

    # The hydrological data are not loaded
    with pytest.raises(psycopg.errors.RaiseException, match="ne sont pas chargées"):
        cursor.execute("SELECT desimper.calculer_ecoulements(1)")

    load_hydro_data(cursor)
    try:
        # Unknown project
        with pytest.raises(psycopg.errors.RaiseException, match="n'existe pas"):
            cursor.execute("SELECT desimper.calculer_ecoulements(-1)")

        # Project (0 0, 100 100): 20 x 20 meshes of 5 m, 10 x 10 starting points every 10 m
        cursor.execute("SELECT desimper.calculer_ecoulements(1, 5, 10, 50)")
        record = cursor.fetchone()
        assert record is not None
        assert record[0] == {"fk_id_projet": 1, "nb_fleches": 400, "nb_lignes": 100}
        assert counts() == (400, 100)

        # Every arrow points to the east, with fully consistent directions
        cursor.execute("""
            SELECT min(angle), max(angle), min(coherence), max(coherence), min(nb_cellules)
            FROM desimper.fleches_ecoulement
            WHERE fk_id_projet = 1
        """)
        assert cursor.fetchone() == (90, 90, 1, 1, 25)

        # Every line goes east, until it leaves the project buffered by 50 m
        cursor.execute("""
            SELECT
                bool_and(ST_YMin(geom) = ST_YMax(geom)),
                min(ST_XMax(geom)), max(ST_XMax(geom)),
                min(longueur), max(longueur)
            FROM desimper.lignes_ecoulement
            WHERE fk_id_projet = 1
        """)
        assert cursor.fetchone() == (True, 150.5, 150.5, 60, 150)

        # Computing again replaces the previous computation
        cursor.execute("SELECT desimper.calculer_ecoulements(1, 5, 10, 50)")
        assert counts() == (400, 100)

        # Changing the project geometry removes the flows
        cursor.execute("""
            UPDATE desimper.projets
            SET geom = ST_Multi(ST_GeomFromText('POLYGON((0 0, 0 200, 200 200, 200 0, 0 0))', 2154))
            WHERE id = 1
        """)
        assert counts() == (0, 0)

        # Deleting the project deletes its flows
        cursor.execute("SELECT desimper.calculer_ecoulements(1)")
        assert counts() == (1600, 400)
        cursor.execute("DELETE FROM desimper.projets WHERE id = 1")
        assert counts() == (0, 0)
    finally:
        cursor.execute(f"TRUNCATE {HYDRO_TABLES}")
