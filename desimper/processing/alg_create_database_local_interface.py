from qgis.core import (
    QgsDataSourceUri,
    QgsProcessingException,
    QgsProviderConnectionException,
    QgsProcessingOutputNumber,
    QgsProcessingOutputString,
    QgsProcessingParameterBoolean,
    QgsProcessingParameterFileDestination,
    QgsProcessingParameterProviderConnection,
    QgsProject,
    QgsProviderRegistry,
    QgsVectorLayer,
    QgsWkbTypes,
)

from ..plugin_tools.i18n import tr
from .base_algorithm import BaseProcessingAlgorithm
from .tools import (
    createAdministrationProjectFromTemplate,
    get_connection_name,
    get_postgis_connection_list,
    plugin_name_normalized,
)


class CreateDatabaseLocalInterface(BaseProcessingAlgorithm):
    CONNECTION_NAME = "CONNECTION_NAME"
    PROJECT_FILE = "PROJECT_FILE"
    ADD_CONTEXTS_LAYERS = "ADD_CONTEXTS_LAYERS"

    OUTPUT_STATUS = "OUTPUT_STATUS"
    OUTPUT_STRING = "OUTPUT_STRING"

    def name(self):
        return "create_database_local_interface"

    def displayName(self):
        return tr("Create database local interface")

    def group(self):
        return tr("Administration")

    def groupId(self):
        return f"{plugin_name_normalized()}_administration"

    def shortHelpString(self):
        return tr(
            "This algorithm will create a new QGIS project file for "
            "administration purpose."
            "\n"
            "\n"
            "The generated QGIS project must then be opened by the administrator "
            "to create the needed data by using QGIS editing capabilities"
            "\n"
            "\n"
            "* PostgreSQL connection to database: name of the database connection "
            "you would like to use for the new QGIS project."
            "\n"
            "* QGIS project file to create: choose the output file destination."
        )

    def initAlgorithm(self, config):
        _ = config
        project = QgsProject.instance()

        connection_name = get_connection_name(project)

        param = QgsProcessingParameterProviderConnection(
            self.CONNECTION_NAME,
            tr("Connection to the PostgreSQL database"),
            "postgres",
            defaultValue=connection_name,
            optional=False,
        )
        param.setHelp(tr("The database where the plugin schema has been installed."))
        self.addParameter(param)

        # target project file
        self.addParameter(
            QgsProcessingParameterFileDestination(
                self.PROJECT_FILE,
                tr("QGIS project file to create"),
                defaultValue="",
                optional=False,
                fileFilter="QGIS project (*.qgs)",
            )
        )

        # Add existing contexts layers
        param = QgsProcessingParameterBoolean(
            self.ADD_CONTEXTS_LAYERS,
            tr(
                "Automatically add layers for existing contexts in the database. "
            ),
            defaultValue=False,
        )
        param.setHelp(
            tr(
                "All the contexts in the database will be added as layers in a group in the QGIS project. "
            )
        )
        self.addParameter(param)

        # OUTPUTS
        # Add output for status (integer)
        self.addOutput(QgsProcessingOutputNumber(self.OUTPUT_STATUS, tr("Output status")))
        # Add output for message
        self.addOutput(QgsProcessingOutputString(self.OUTPUT_STRING, tr("Output message")))

    def checkParameterValues(self, parameters, context):
        # Check that the connection name has been configured
        connection_name = parameters[self.CONNECTION_NAME]
        if not connection_name:
            return False, tr('You must use the "Configure plugin" alg to set the database connection name')

        # Check that it corresponds to an existing connection
        if connection_name not in get_postgis_connection_list():
            return False, tr("The configured connection name does not exists in QGIS")

        # Check if the target project file ends with qgs
        project_file = self.parameterAsString(parameters, self.PROJECT_FILE, context)
        if not project_file.endswith(".qgs"):
            return False, tr('The QGIS project file name must end with extension ".qgs"')

        return super(CreateDatabaseLocalInterface, self).checkParameterValues(parameters, context)

    def processAlgorithm(self, parameters, context, feedback):
        # Database connection parameters
        connection_name = parameters[self.CONNECTION_NAME]

        # Write the file out again
        project_file = self.parameterAsString(parameters, self.PROJECT_FILE, context)
        if not createAdministrationProjectFromTemplate(connection_name, project_file):
            raise QgsProcessingException(f"Connection {connection_name} not found")

        # Add contextes data if desired
        if self.parameterAsBool(parameters, self.ADD_CONTEXTS_LAYERS, context):
            admin_project = QgsProject()
            if not admin_project.read(project_file):
                raise QgsProcessingException(
                    "{}: {}".format(tr("Could not read the created QGIS project"), project_file)
                )
            self._add_contexts_layers(admin_project, parameters, context, feedback)
            admin_project.write()

        msg = tr("QGIS Administration project has been successfully created from database connection")
        msg += ": {}".format(connection_name)
        feedback.pushInfo(msg)
        status = 1

        return {self.OUTPUT_STATUS: status, self.OUTPUT_STRING: msg}

    def _add_contexts_layers(self, project, parameters, context, feedback, group_name="Contextes"):
        # Connection name
        connection_name = self.parameterAsConnectionName(parameters, self.CONNECTION_NAME, context)
        if not connection_name:
            return False, tr("No valid database connection provided.")
        metadata = QgsProviderRegistry.instance().providerMetadata("postgres")
        connection = metadata.findConnection(connection_name)
        if not connection:
            return False, tr("Could not create a connection to the database with the given connection name.")

        # Add group for contextes
        root = project.layerTreeRoot()
        group = root.findGroup(group_name)
        if not group:
            group = root.addGroup(group_name)

        # Get list of contexts
        query = ("""
            SELECT nom_schema, nom_table
            FROM desimper.liste_contextes
        """)

        try:
            data = connection.executeSql(query)
        except QgsProviderConnectionException as e:
            msg = tr("* Failed to get list of contexts")
            msg += f" ({e!s})"
            feedback.pushInfo(msg)
            return False, msg

        # Add context layers
        for row in data:
            schema_name = row[0]
            table_name = row[1]
            try:
                # Create layer
                uri = QgsDataSourceUri(connection.uri())
                uri.setDataSource(
                    f"{schema_name}",
                    f"{table_name}",
                    "geom",
                    aKeyColumn="id"
                )
                uri.setWkbType(QgsWkbTypes.MultiPolygon)
                source = QgsVectorLayer(uri.uri(), f"{table_name}", "postgres")
                assert source.isValid(), source.error().message()
                # Add layer
                project.addMapLayer(source, False)
                group.addLayer(source)

            except Exception as e:
                msg = tr("* Failed to create layer for context")
                msg += f" {schema_name}.{table_name} ({e!s})"
                feedback.pushInfo(msg)
                return False, msg

        return True, ""
