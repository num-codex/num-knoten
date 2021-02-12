#!/bin/sh

export COMPOSE_IGNORE_ORPHANS=True
export COMPOSE_PROJECT=num-knoten

echo "Create num node docker network, if it does not exist..."
if [ ! "$(docker network ls | grep num-node)" ]; then
docker network create num-node
fi

FILE=$PWD/node-rev-proxy/dhparam.pem
if [ ! -f "$FILE" ]; then
    echo "Creating longer Diffie-Hellman Prime for extra security... this may take a while \n\n"
    docker run --rm -v $PWD/node-rev-proxy:/export --entrypoint openssl alpine/openssl dhparam -out /export/dhparam.pem 4096
    echo $FILE
    
fi

echo "Generating default certificate..."
cd node-rev-proxy && bash generateCert.sh

echo "generating user: $1 , with password: $2"
docker run --rm --entrypoint htpasswd registry:2.7.0 -nb $1 $2 > .htpasswd
