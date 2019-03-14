#!/bin/bash

export AWS_SECURITY_GROUP_NAME=MySecurityGroup
export INSTANCE_SCRIPT=configure_aws_instance.sh
export NOTEBOOK=test_aws_instance.ipynb
export MY_KEY_NAME=CSE89
export IMAGE_ID=ami-06ae1bbcb7042c6c6
export INSTANCE_TYPE=p3.8xlarge
export REGION=eu-central-1
export INSTANCE_USER_NAME=ec2-user
export PATH_TO_KEY=
export LOCAL_JUPYTER_PORT_TO_USE=8899

# Make sure the permissions on the .pem file are correct
chmod 400 ${PATH_TO_KEY}${MY_KEY_NAME}.pem

# First we need to figure out our public IP-address so we can limit
# access to our AWS instance to this IP
MY_IP_ADDRESS="$(curl -s http://whatismyip.akamai.com)"

# First we define a security group with access for SSH (port 22)
# and Jupyter notebooks (port 8888)
EXISTING_AWS_SECURITY_GROUP=`aws ec2 describe-security-groups --filters \
  "Name=group-name,Values=${AWS_SECURITY_GROUP_NAME}" --query 'SecurityGroups[*].GroupName' --output text`
if [ "${AWS_SECURITY_GROUP_NAME}" == "${EXISTING_AWS_SECURITY_GROUP}" ]; then
  echo "Removing the currently defined AWS Security Group called ${AWS_SECURITY_GROUP_NAME}..."
  aws ec2 delete-security-group --group-name ${AWS_SECURITY_GROUP_NAME}
fi
echo "Creating new AWS Security group..."
AWS_SECURITY_GROUP_ID=`aws ec2 create-security-group --group-name ${AWS_SECURITY_GROUP_NAME} \
  --description "Security Group for EC2 instances to facilitate Jupyter notebook"`
aws ec2 authorize-security-group-ingress --group-name ${AWS_SECURITY_GROUP_NAME} \
  --protocol tcp --port 22 --cidr ${MY_IP_ADDRESS}/32
aws ec2 authorize-security-group-ingress --group-name ${AWS_SECURITY_GROUP_NAME} \
  --protocol tcp --port 8888 --cidr ${MY_IP_ADDRESS}/32

export INSTANCE_ID=`aws ec2 run-instances --image-id ${IMAGE_ID} --count 1 \
  --instance-type ${INSTANCE_TYPE} --key-name ${MY_KEY_NAME} \
  --security-groups ${AWS_SECURITY_GROUP_NAME} --region ${REGION} \
  --query 'Instances[0].InstanceId' --output text`

STATUS=
echo "Starting instance $INSTANCE_ID of type ${INSTANCE_TYPE}..."
echo "  This can take a couple of minutes..."
s=0
while ! [ "${STATUS}" == 'ok' ]; do
  STATUS=`aws ec2 describe-instance-status --instance-id ${INSTANCE_ID} \
    --query 'InstanceStatuses[0].InstanceStatus.Status' --output text`
  let "s+=1"
  if [ ${s} -ge 5 ] && ! [ "${STATUS}" == 'ok' ]; then
    s=0
    echo "    Still initializing..."
  fi
  sleep 5
done

export DNS_NAME=`aws ec2 describe-instances --instance-id ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].PublicDnsName' --output text`
echo "Instance ${INSTANCE_ID} is now ready at ${DNS_NAME}!"
echo ""

# Make sure that your key (the BLAH.pem file), your instance configuration script
# and your notebook are all in the working directory from which you are running
# this script. Or adjust this script to accomodate of course.
echo "Copying configuration script and notebook to the instance..."
scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ${INSTANCE_SCRIPT} \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME} \

scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ${NOTEBOOK} \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME} \

echo "SSH'ing to the instance..."
ssh -L localhost:${LOCAL_JUPYTER_PORT_TO_USE}:localhost:8888 \
  -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
  ${INSTANCE_USER_NAME}@${DNS_NAME} \
