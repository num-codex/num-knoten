#!/bin/sh

for file in odm2fhir/out/*.json; do
    echo -n "Uploading file $file ... "
    result=`curl -L -H 'Content-Type:application/fhir+json' -d "@$file" --write-out "%{http_code}\n" --silent --output /dev/null http://localhost:18080/fhir`
    if [ $result = "200" ] 
    then
        echo "OK"
    else
        echo "FAILURE, code = $result"
    fi
done