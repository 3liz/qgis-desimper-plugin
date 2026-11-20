"""Tests for Processing algorithms."""

import unittest

from pathlib import Path

import psycopg

from qgis import processing

from desimper.plugin_tools.feedback import LoggerProcessingFeedBack
from desimper.plugin_tools.resources import (
    available_migrations,
    schema_version,
)
from desimper.processing.database import CreateDatabaseStructure, UpgradeDatabaseStructure
from desimper.processing.provider import Provider

# This list must not be changed
# as it correspond to the list of tables
# created for the first version
TABLES_FOR_FIRST_VERSION = [
    "communes",
    "contextes_projets",
    "liste_contextes",
    "metadata",
    "nomenclature_destinations",
    "nomenclature_pollution",
    "nomenclature_revetements",
    "nomenclature_type_projet",
    "nomenclature_usages_surface",
    "pluviometrie",
    "projets",
    "surfaces_projet",
    "variantes",
]

# Expected list of tables for current version
# Must be changed any time the SQL structure is changed
TABLES_FOR_CURRENT_VERSION = sorted(
    [
        *TABLES_FOR_FIRST_VERSION,
        "bassins_versants",
        "fleches_ecoulement",
        "lignes_ecoulement",
        "hydro_bv_amont",
        "hydro_codes_d8",
        "hydro_d8_raster",
        "hydro_grille",
        "hydro_noeuds",
        "hydro_troncons",
    ]
)


def check_hydro_tables(cursor: psycopg.Cursor, schema: str):
    """The TauDEM D8 coding is installed, the hydrological data are not"""
    cursor.execute(f"SELECT count(*) FROM {schema}.hydro_codes_d8")
    assert cursor.fetchone() == (8,)
    cursor.execute(f"SELECT count(*) FROM {schema}.hydro_grille")
    assert cursor.fetchone() == (0,)


def test_processing_create(
    processing_provider: Provider,
    db_connection: psycopg.Connection,
    db_schema: str,
):
    """Test the processing algorithm for creating the database structure."""

    params = {
        "CONNECTION_NAME": "test",
        "OVERRIDE": True,
    }

    feedback = LoggerProcessingFeedBack()

    # Run create database structure alg
    alg = f"{processing_provider.id()}:create_database_structure"
    processing_output = processing.run(alg, params, feedback=feedback)

    assert processing_output["OUTPUT_STATUS"] == 1
    assert processing_output["OUTPUT_VERSION"] == schema_version()

    check_hydro_tables(db_connection.cursor(), db_schema)


def test_upgrade_from(
    db_schema: str,
    db_install_version: int,
    db_connection: psycopg.Connection,
    processing_provider: Provider,
    data: Path,
):
    """Test the algorithms for creating and updating the database structure."""

    current_version = schema_version()

    print("\n::test_upgrade_from::current_version::", current_version)
    print("::test_upgrade_from::db_install_version::", db_install_version)
    print("::test_upgrade_from::available_migrations::", available_migrations())

    assert db_install_version is not None, "This test require at least one available upgrade"
    assert current_version >= db_install_version, (
        "Current schema version cannot be lower than install version"
    )

    # Get the installation dir of the first version
    test_version = 1
    install_dir = data.joinpath(f"install-version-{test_version}", "sql")
    assert install_dir.exists()

    feedback = LoggerProcessingFeedBack()

    # Create the database from the first version
    # (all the migrations will be applied by the upgrade below)
    CreateDatabaseStructure.create_database(
        "test",
        db_schema,
        version=test_version,
        override=True,
        install_dir=install_dir,
        feedback=feedback,
    )

    case = unittest.TestCase()

    provider_id = processing_provider.id()

    cursor = db_connection.cursor()

    # Check the list of tables and views from the database
    cursor.execute(
        f"""
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = '{db_schema}'
        ORDER BY table_name
        """
    )
    records = cursor.fetchall()
    result = [r[0] for r in records]

    # Expected tables in the specific version written above at the beginning of the test.
    # DO NOT CHANGE HERE, change below at the end of the test.
    case.assertCountEqual(TABLES_FOR_FIRST_VERSION, result)
    assert result == TABLES_FOR_FIRST_VERSION

    # Check if the version has been written in the metadata table
    sql = f"""
        SELECT me_version
        FROM {db_schema}.metadata
        WHERE me_status = 1
        ORDER BY me_version_date DESC
        LIMIT 1;
    """
    cursor.execute(sql)
    record = cursor.fetchone()
    assert record is not None
    assert int(record[0]) == test_version

    # Run the update database structure alg
    # Since the structure has been created with db_install_version above
    # The expected list of tables
    feedback.pushDebugInfo("Update the database")

    UpgradeDatabaseStructure.upgrade_database(
        "test",
        db_schema,
        run_migrations=True,
        feedback=feedback,
    )
    # Check if the version has been written in the metadata table
    sql = f"""
        SELECT me_version
        FROM {db_schema}.metadata
        WHERE me_status = 1
        ORDER BY me_version_date DESC
        LIMIT 1;
    """
    cursor.execute(sql)
    record = cursor.fetchone()
    assert record is not None
    assert int(record[0]) == current_version

    # Check the list of tables
    cursor.execute(
        f"""
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = '{db_schema}'
        ORDER BY table_name
        """
    )
    records = cursor.fetchall()
    result = [r[0] for r in records]
    case.assertCountEqual(TABLES_FOR_CURRENT_VERSION, result)

    # The hydrological tables are created by the migrations
    check_hydro_tables(cursor, db_schema)

    # Create the database structure with override
    # This will delete and recreate the structure for the last version
    feedback.pushDebugInfo("Relaunch the algorithm without override")
    params = {
        "CONNECTION_NAME": "test",
        "OVERRIDE": True,
    }

    # Check we need to run upgrade or not
    feedback.pushDebugInfo("Update the database")
    params = {"CONNECTION_NAME": "test", "RUN_MIGRATIONS": True}
    alg = f"{provider_id}:upgrade_database_structure"
    results = processing.run(alg, params, feedback=feedback)
    assert results["OUTPUT_STATUS"] == 1
    assert results["OUTPUT_STRING"] == (
        " The database version already matches the plugin version. No upgrade needed."
    )

    # Check the list of tables
    cursor.execute(
        f"""
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = '{db_schema}'
        ORDER BY table_name
        """
    )
    records = cursor.fetchall()
    result = [r[0] for r in records]

    case.assertCountEqual(TABLES_FOR_CURRENT_VERSION, result)

    assert result == TABLES_FOR_CURRENT_VERSION
