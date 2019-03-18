#!/bin/bash
export AWS_SECURITY_GROUP_NAME=MySecurityGroup
export INSTANCE_SCRIPT=configure_aws_instance.sh
export MY_KEY_NAME=MyKey
export IMAGE_ID=ami-06ae1bbcb7042c6c6
export INSTANCE_TYPE=t2.micro
export REGION=eu-central-1
export INSTANCE_USER_NAME=ec2-user
export PATH_TO_KEY=../
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
  if ! [ "${STATUS}" == 'ok' ]; then
    if [ ${s} -ge 5 ] ; then
      s=0
      echo "    Still initializing..."
    fi
    sleep 5
  fi
done

export DNS_NAME=`aws ec2 describe-instances --instance-id ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].PublicDnsName' --output text`
echo "Instance ${INSTANCE_ID} is now ready at ${DNS_NAME}!"
echo ""

# Make sure that your key (the BLAH.pem file), your instance configuration script
# and your notebook are all in the working directory from which you are running
# this script. Or adjust this script to accomodate of course.
echo "Copying configuration scripts and notebooks to the instance..."
scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null  *.sh \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME}

scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  ~/.kaggle/kaggle.json \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME}

scp -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  *.ipynb \
  ${INSTANCE_USER_NAME}@${DNS_NAME}:/home/${INSTANCE_USER_NAME}

echo "Using SSH to run the configuration script on the instance."
ssh -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
  ${INSTANCE_USER_NAME}@${DNS_NAME} "bash ${INSTANCE_SCRIPT}"

echo "SSH'ing to the instance in the background to forward port 8888"
echo "on the instance to port ${LOCAL_JUPYTER_PORT_TO_USE} on the local machine."
ssh -fNT -L localhost:${LOCAL_JUPYTER_PORT_TO_USE}:localhost:8888 \
  -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
  ${INSTANCE_USER_NAME}@${DNS_NAME}

echo "Getting the Jupyter server URL."
NOTEBOOK_SERVER_TOKEN=
s=0
while [ "${NOTEBOOK_SERVER_TOKEN}" == '' ]; do
  export NOTEBOOK_SERVERS=`ssh -i ${PATH_TO_KEY}${MY_KEY_NAME}.pem \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q \
    ${INSTANCE_USER_NAME}@${DNS_NAME} "jupyter notebook list"`
  REST=${NOTEBOOK_SERVERS#*token}
  TOKEN_START_INDEX=$(( ${#NOTEBOOK_SERVERS} - ${#REST} + 1 ))
  REST2=${NOTEBOOK_SERVERS#*::}
  TOKEN_LENGTH=$(( ${#REST} - 6 - ${#REST2} + 2))
  if [ ${TOKEN_LENGTH} -ge 1 ] ; then
    export NOTEBOOK_SERVER_TOKEN=${NOTEBOOK_SERVERS:${TOKEN_START_INDEX}:${TOKEN_LENGTH}}
    break
  fi
  let "s+=1"
  if [ ${s} -ge 5 ] ; then
    s=0
    echo "    Still waiting for the Jupyter server to come available..."
  fi
  sleep 5
done

echo "Opening browser with the Jupyter interface."
/usr/bin/open "http://localhost:${LOCAL_JUPYTER_PORT_TO_USE}/?token=${NOTEBOOK_SERVER_TOKEN}"
