#!/bin/bash

scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME}/${NOTEBOOK} .

echo "Instance ${INSTANCE_ID} is now terminating."
export blah=`aws ec2 terminate-instances --instance-id ${INSTANCE_ID}`
