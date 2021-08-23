#!/bin/bash

function usage() {
	echo "USAGE:"
	echo ""
    echo "	./em-demo-script.sh <EM URL:PORT>"
    echo ""
}

if [ $# -eq 0 ]; then
	echo ""
	echo "em-demo-script.sh requires EM URL to start. Please pass the EM URL"
	echo ""
	usage
	exit 1
fi

EM_URL=$1

echo "EM URL -  ${EM_URL}"

expone=$(curl -s -X POST ${EM_URL}/createExperiment -H "Content-Type: application/json"  -d @./input-512.json)
echo "Trial - 1 : id - ${expone}"
sleep 2
exptwo=$(curl -s -X POST ${EM_URL}/createExperiment -H "Content-Type: application/json"  -d @./input-510.json)
echo "Trial - 2 : id - ${exptwo}"

for ((i=1;i<=100;i++));
do
	echo -n "Status of first trial with id - ${expone} : "
	outone=$(curl -s -X POST ${EM_URL}/getTrialStatus -H "Content-Type: application/json" -d "{\"runId\":\"${expone}\"}")
	echo "${outone}"
	echo -n "Status of second trial with id - ${exptwo} : "
	outtwo=$(curl -s -X POST ${EM_URL}/getTrialStatus -H "Content-Type: application/json" -d "{\"runId\":\"${exptwo}\"}")
	echo "${outtwo}"
   	sleep 10
done