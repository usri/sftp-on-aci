#!/bin/bash -e

# Create the SFTP resource group
echo "Creating SFTP infrastructure resource group '$SFTP_RG_NAME' in region '$SFTP_LOCATION'."
az group create --name $SFTP_RG_NAME --location $SFTP_LOCATION --output none

# Deploy the SFTP solution
az deployment group create --resource-group $SFTP_RG_NAME --template-file ./azure-deploy.json \
    --parameters keyVaultName=$KV_NAME \
    kvSecretsTagName=$KV_TAG_NAME \
    kvSecretsTagValue=$KV_TAG_VALUE \
    managedIdentityResourceId=$MI_RESOURCE_ID \
    helperScriptUrl=$HELPER_SCRIPT_URL