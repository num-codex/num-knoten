#!/bin/bash

set -e

while ! ping -c 1 -n -w 1 i2b2-app &> /dev/null
do
    printf "%c" "."
    sleep 1
done

sed -i.bak -e "s/#listen_addresses = 'localhost'/listen_addresses = '*'\t/" /etc/postgresql/13/main/postgresql.conf

IP_ADDR=`/usr/bin/dig +short i2b2-app`
cat << EOF >> /etc/postgresql/13/main/pg_hba.conf

# TYPE  DATABASE        USER            ADDRESS                        METHOD
host    all             i2b2pm          ${IP_ADDR}/32 md5
host    all             i2b2hive        ${IP_ADDR}/32 md5
host    all             i2b2metadata    ${IP_ADDR}/32 md5
host    all             i2b2demodata    ${IP_ADDR}/32 md5
host    all             i2b2imdata      ${IP_ADDR}/32 md5
host    all             i2b2workdata    ${IP_ADDR}/32 md5
host    all             postgres        ${IP_ADDR}/32 md5
EOF

for CIDR_ENTRY in ${ALLOWED_ETL_HOSTS//;/ }; do
cat << EOF >> /etc/postgresql/13/main/pg_hba.conf

host    all             i2b2pm          ${ALLOWED_ETL_HOSTS} md5
host    all             i2b2hive        ${ALLOWED_ETL_HOSTS} md5
host    all             i2b2metadata    ${ALLOWED_ETL_HOSTS} md5
host    all             i2b2demodata    ${ALLOWED_ETL_HOSTS} md5
host    all             i2b2imdata      ${ALLOWED_ETL_HOSTS} md5
host    all             i2b2workdata    ${ALLOWED_ETL_HOSTS} md5
host    all             postgres        ${ALLOWED_ETL_HOSTS} md5
EOF
done

# Enable access to 'custom' i2b2 projects in Postgres:

CUSTOM_PROJECTS=`cat /miracum-scripts/projects.txt`
for PROJECT in ${CUSTOM_PROJECTS//;/ }; do
cat << EOF >> /etc/postgresql/13/main/pg_hba.conf

host    all             $PROJECT          ${IP_ADDR}/32 md5
EOF
for CIDR_ENTRY in ${ALLOWED_ETL_HOSTS//;/ }; do
cat << EOF >> /etc/postgresql/13/main/pg_hba.conf

host    all             $PROJECT          ${ALLOWED_ETL_HOSTS} md5
EOF
done
done

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Starting DB for setting instance-specific configuration.\n"
/etc/init.d/postgresql start

echo "Waiting for DB to come up"
while [ `/usr/lib/postgresql/13/bin/pg_ctl status -D /etc/postgresql/13/main/ | grep -c "server is running"` != "1" ]
do
    printf "%c" "."
    sleep 1
done
sleep 10

DEFAULT_PW=Phoo4eih

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Setting instance-specific DB passwords.\n"
psql -d i2b2 -c "ALTER USER i2b2metadata WITH PASSWORD '${I2B2METADATA_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER i2b2hive WITH PASSWORD '${I2B2HIVE_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER i2b2pm WITH PASSWORD '${I2B2PM_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER i2b2demodata WITH PASSWORD '${I2B2DEMODATA_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER i2b2workdata WITH PASSWORD '${I2B2WORKDATA_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER i2b2imdata WITH PASSWORD '${I2B2IMDATA_PW:-${DEFAULT_PW}}'"
psql -d i2b2 -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_PW:-${DEFAULT_PW}}'"

function hashit {
    java -cp /var/lib/postgresql/PWHash/commons-logging-1.2.jar:/var/lib/postgresql/PWHash PWHash $1
}

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Setting instance-specific UI passwords.\n"
psql -d i2b2 -c "UPDATE i2b2pm.pm_user_data SET password='`hashit ${INITIAL_WEBUI_DEMO_PW-${DEFAULT_PW}}`',          entry_date=current_timestamp WHERE user_id='demo'                AND change_date is NULL"
psql -d i2b2 -c "UPDATE i2b2pm.pm_user_data SET password='`hashit ${INITIAL_WEBUI_I2B2_PW-${DEFAULT_PW}}`',          entry_date=current_timestamp WHERE user_id='i2b2'                AND change_date is NULL"
psql -d i2b2 -c "UPDATE i2b2pm.pm_user_data SET password='`hashit ${INITIAL_AGG_SERVICE_ACCOUNT_PW:-demouser}`', entry_date=current_timestamp WHERE user_id='AGG_SERVICE_ACCOUNT' AND change_date is NULL"

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Setting Webservice-Endpoints.\n"
/etc/postgresql/13/main/setEndpoints.sh ${DWH_HOST} ${PORT_REST}

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Configuration done. Stopping DB.\n"
/etc/init.d/postgresql stop
echo "Waiting for DB to shut down"
while [ `/usr/lib/postgresql/13/bin/pg_ctl status -D /etc/postgresql/13/main/ | grep -c "no server running"` != "1" ]
do
    printf "%c" "."
    sleep 1
done
sleep 3

printf "$(date -u '+%y-%m-%d %H:%M:%S') UTC:  Starting actual DB service.\n"
exec /usr/lib/postgresql/13/bin/postgres -D /var/lib/postgresql/13/main/ -c config_file=/etc/postgresql/13/main/postgresql.conf
