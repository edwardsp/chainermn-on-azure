#!/bin/bash

RESOURCE_GROUP=$1
VMSS_NAME="vmss"

az vmss nic list -g ${RESOURCE_GROUP} --vmss-name ${VMSS_NAME} \
--query "[*].ipConfigurations[0].privateIpAddress" -o tsv > ~/hosts.txt
