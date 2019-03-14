#!/bin/bash

# Configuring the AWS CLI

# First we install the AWS Command Line Interface:
echo ""
echo "Installing the AWS Command Line Interface..."
yes | pip install awscli --upgrade --user

# Add a line following line to your .bash_profile, so that the 'aws' command is recognised:
echo 'export PATH=~/.local/bin:$PATH' >> ~/.bash_profile

source ~/.bash_profile

# Now we configure your AWS credentials and region with `aws configure`.
# This will ask for your access keys and some other configurations,
# and will create a `credentials` and `config` file in your ~/.aws/ folder.
# You can get access keys from the Users page in the
# Identity and Access Management section of the AWS console:
#   https://console.aws.amazon.com/iam/home#/users
echo ""
echo "Let's configure your AWS access..."
echo "(Get your keys at https://console.aws.amazon.com/iam/home?region=eu-central-1#/users)"
aws configure
