#!/bin/bash

export HOST_ADDRESS=$1
export PORT=$2

psql -d i2b2 -c "UPDATE i2b2pm.pm_cell_data SET url='http://${HOST_ADDRESS}:${PORT}/i2b2/services/QueryToolService/' WHERE cell_id='CRC'"
psql -d i2b2 -c "UPDATE i2b2pm.pm_cell_data SET url='http://${HOST_ADDRESS}:${PORT}/i2b2/services/FRService/'        WHERE cell_id='FRC'"
psql -d i2b2 -c "UPDATE i2b2pm.pm_cell_data SET url='http://${HOST_ADDRESS}:${PORT}/i2b2/services/IMService/'        WHERE cell_id='IM'"
psql -d i2b2 -c "UPDATE i2b2pm.pm_cell_data SET url='http://${HOST_ADDRESS}:${PORT}/i2b2/services/OntologyService/'  WHERE cell_id='ONT'"
psql -d i2b2 -c "UPDATE i2b2pm.pm_cell_data SET url='http://${HOST_ADDRESS}:${PORT}/i2b2/services/WorkplaceService/' WHERE cell_id='WORK'"
