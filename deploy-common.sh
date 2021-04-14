#!/bin/bash -e

# Create the common resource group
echo "Creating common infrastructure resource group '$COMMON_RG_NAME' in region '$COMMON_LOCATION'."
az group create --name $COMMON_RG_NAME --location $COMMON_LOCATION --output none

# Create managed identity
echo "Creating user-assigned managed identity '$MI_ID_NAME'."
MI_ID=$(az identity create --resource-group $COMMON_RG_NAME --name $MI_ID_NAME --query principalId --output tsv)
MI_RESOURCE_ID=$(az resource show --resource-group $COMMON_RG_NAME --name $MI_ID_NAME --resource-type "Microsoft.ManagedIdentity/userAssignedIdentities" --query id --output tsv)

# Create key vault and assign access policy for managed identity
echo "Creating key vault '$KV_NAME'."
az keyvault create --name $KV_NAME --resource-group $COMMON_RG_NAME --location $COMMON_LOCATION --output none
echo "Setting key vault policy (get/list secrets) for '$MI_ID_NAME'."
az keyvault set-policy --name $KV_NAME --object-id $MI_ID --secret-permissions get list --output none

# Create storage account and upload the 'deploy-helper.sh' script
CONTAINER_NAME="sftp-scripts"
HELPER_SCRIPT_LOCAL="./deploy-helper.sh"
HELPER_SCRIPT_BLOB=$(cut -d '/' -f2 <<< $HELPER_SCRIPT_LOCAL)

echo "Creating storage account '$STG_ACCT_NAME'."
az storage account create --resource-group $COMMON_RG_NAME --name $STG_ACCT_NAME --output none
STG_CONN_STRING=$(az storage account show-connection-string --name $STG_ACCT_NAME --output tsv)

echo "Creating blob container '$CONTAINER_NAME' in storage account '$STG_ACCT_NAME'."
az storage container create --name $CONTAINER_NAME --connection-string $STG_CONN_STRING --public-access blob --output none

echo "Uploading $HELPER_SCRIPT_LOCAL to blob container '$CONTAINER_NAME'."
az storage blob upload -f $HELPER_SCRIPT_LOCAL -c $CONTAINER_NAME -n $HELPER_SCRIPT_BLOB --connection-string $STG_CONN_STRING --output none
HELPER_SCRIPT_URL=$(az storage blob url --container-name $CONTAINER_NAME --name $HELPER_SCRIPT_BLOB --connection-string $STG_CONN_STRING --output tsv)

echo ""
echo "Common resources have been successfully provisioned and configured."
echo ""
