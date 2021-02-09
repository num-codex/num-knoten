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
    echo $FILE
    openssl dhparam -out $FILE 4096
fi

cd node-rev-proxy && bash generateCert.sh
echo "generating user and pw: $1  ,  $2"
docker run --rm --entrypoint htpasswd registry:2.7.0 -nb $1 $2 > .htpasswd
