#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten
FILE=$PWD/node-rev-proxy/dhparam.pem

if [ ! -f "$FILE" ]; then
    echo "Creating longer Diffie-Hellman Prime for extra security... this may take a while..."
    docker run --rm -v "$PWD/node-rev-proxy:/export" --entrypoint openssl alpine/openssl dhparam -out /export/dhparam.pem 4096
    echo "$FILE"
fi

echo "Generating default certificate..."
cd node-rev-proxy && bash generateCert.sh
echo "Finished certificate generation."

echo "Generating user: $1 , with password: $2"
docker run --rm --entrypoint htpasswd registry:2.7.0 -nb $1 $2 >.htpasswd
echo "Finished user generation."
