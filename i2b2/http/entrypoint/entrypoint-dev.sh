#!/bin/bash

sed -i.bak "s/\${DWH_HOST}/${DWH_HOST}/g" /var/www/html/webclient/index.php
sed -i.bak "s/\${DWH_HOST}/${DWH_HOST}/g" /var/www/html/admin/index.php
sed -i.bak "s#https://i2b2-app/i2b2/services#http://${DWH_HOST}:${PORT_REST}/i2b2/services#" /var/www/html/admin/i2b2_config_data.js
sed -i.bak "s#https://i2b2-app/i2b2/services#http://${DWH_HOST}:${PORT_REST}/i2b2/services#" /var/www/html/webclient/i2b2_config_data.js

/usr/sbin/apache2ctl -D FOREGROUND
