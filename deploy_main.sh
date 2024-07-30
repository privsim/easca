#!/bin/bash

# Set the base directory
BASE_DIR="$(pwd)"

# Function to prompt for environment variables
prompt_for_env_vars() {
    read -p "Enter your domain (e.g., example.com): " BASE_DOMAIN
    read -p "Enter your ACME email: " ACME_EMAIL
    read -p "Enter your Cloudflare DNS API token: " CF_DNS_API_TOKEN
    read -p "Enter Redis password: " REDIS_PASS
    read -p "Enter MariaDB root password: " MARIA_ROOT_PASS
    read -p "Enter MariaDB user password: " MARIA_USER_PASS
    read -p "Enter SMTP relay: " SMTP_RELAY
    read -p "Enter SMTP login: " SMTP_LOGIN
    read -p "Enter Cloudflare Zero Trust name: " CF_ZEROTRUST_NAME
    read -p "Enter Cloudflare secret: " CF_SECRET
    read -p "Enter first user's name: " USER1
    read -p "Enter first user's email: " EMAIL_USER1
    read -s -p "Enter first user's password: " USER1_PASS
    echo
    read -p "Enter second user's name: " USER2
    read -p "Enter second user's email: " EMAIL_USER2
    read -s -p "Enter second user's password: " USER2_PASS
    echo
}

# Function to hash passwords using Argon2
hash_password() {
    docker run --rm authelia/authelia:latest authelia hash-password "$1" | sed 's/Password hash: //g'
}

# Main script
echo "Welcome to the Headscale deployment script!"
prompt_for_env_vars

# Export environment variables
export BASE_DIR BASE_DOMAIN ACME_EMAIL CF_DNS_API_TOKEN REDIS_PASS MARIA_ROOT_PASS MARIA_USER_PASS
export SMTP_RELAY SMTP_LOGIN CF_ZEROTRUST_NAME CF_SECRET
export USER1 EMAIL_USER1 USER2 EMAIL_USER2

# Hash user passwords
export ARGON_HASHED_USER1_PASS=$(hash_password "$USER1_PASS")
export ARGON_HASHED_USER2_PASS=$(hash_password "$USER2_PASS")

# Run deploy_01.sh
echo "Running deploy_01.sh..."
bash "${BASE_DIR}/deploy_01.sh"

# Run deploy_02.sh
echo "Running deploy_02.sh..."
bash "${BASE_DIR}/deploy_02.sh"

echo "Deployment complete!"