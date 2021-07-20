# SFTP on Azure Container Instances (ACI)

This sample provides guidance and code to host an SFTP server using an Azure Container Instance (ACI).  The solution builds on an existing [Azure code sample](https://docs.microsoft.com/en-us/samples/azure-samples/sftp-creation-template/sftp-on-azure/) and provides additional capabilities, such as

- support for multiple SFTP user credentials,
- integration with Azure Key Vault, whereby SFTP user credentials are stored and managed in Key Vault, and
- ability to "tag" SFTP user credentials stored in key vault to support multiple SFTP deployment regions.

## Architecture

The solution is designed in a way that de-couples _common_ resources (Key Vault, Managed Identity), from the deployment of the SFTP resources (Container Instance, FileShare).  This enables you to have multiple deployments, perhaps in different regions, that can integrate with a single Key Vault instance.  It also simplifies creating and managing the SFTP users for operations, since there is just one Key Vault and Managed Identity to work with.

The diagram below illustrates the architecture this solution deploys.

![sftp-on-aci](/assets/sftp-on-aci.png)

## Pre-Requisites

To use the solution, you must meet the following pre-requisites:

- Azure Subscription (commercial or government) 
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli), v2.18 (or newer)
- [File Zilla](https://filezilla-project.org/) or other FTP client that supports SFTP

> This guidance was developed and tested on Ubuntu 18.04 LTS and Ubuntu 20.04 LTS.  You could also use an Azure Cloud Shell (bash) to configure and deploy the solution.

## Get Started

This section will guide you through the steps to deploy the _common_ resources, add SFTP users to Key Vault, and deploy one or more stamps/instances of the SFTP solution.

### Sign-in to your Azure subscription

The sections below require you to be signed-in to your Azure subscription, and in the `sftp` folder, so do this first.

```bash
az login
cd ./sftp-on-aci
```

### Deploy the _common_ resources

The _common_ resources in this solution include a _Key Vault_, _Storage Account_, and a _User-assigned Managed Identity_.  The _Key Vault_ is where you will setup and manage your SFTP user credentials.  Guidance on how to do that is later in this document.

The _Storage Account_ will store the `deploy-helper.sh` script.  The Azure Resource Manager will execute this script during the SFTP deployment.  Therefore, it needs to be accessible via URL for the Azure Resource Manager to access it.

The _User-assigned Managed Identity_ is used by the Azure Resource Manager during the SFTP Deployment to execute the `deploy-helper.sh` script.  Meaning, the **identity** of the process executing the `deploy-helper.sh` script will be this user-assigned managed identity.  This identity will be configured with permissions to _get_ and _list_ secrets (SFTP user credentials) in the _Key Vault_.  

> NOTE: You only need to deploy the _common_ resources (this section) one time.  These resources are used by one or more instances of the SFTP solution you will deploy later in this document.

To prepare for the deployment of the _common_ resources, set and save the environment variables listed below to a `.env` file to personalize your deployment.  You only need to specificy the `UNIQUE_ID`.  However, if you want to change the naming convention for the other environment variables you're free to do so.

```bash
# Set a unique identifier to use in Azure resource names to avoid DNS conflicts
UNIQUE_ID=""

# Convert UNIQUE_ID to lowercase
UNIQUE_ID=$(echo "$UNIQUE_ID" | tr '[:upper:]' '[:lower:]')

# Remove any '-' characters in the UNIQUE_ID
UNIQUE_ID=$(echo "${UNIQUE_ID//-}")

# Common resoure group settings
COMMON_RG_NAME=sftp-common-rg              # Resource group name for common resources
COMMON_LOCATION=eastus                     # az account list-locations --query '[].name'

# Key Vault settings
KV_NAME=sft-common-${UNIQUE_ID}-kv         # Must be globally unique

# Managed Identity settings
MI_ID_NAME=sftp-kv-helper-${UNIQUE_ID}-mi  # Must be unique to your AAD tenant

# Azure storage account settings
STG_ACCT_NAME=sftpcommon${UNIQUE_ID}stg    # Must be globally unique, lowercase
```

Next, execute the `deploy-common.sh` script.

```bash
# Source and export the environment variables
set -a  
source .env
set +a

# Deploy the common resources.  Pay attention to the ". ./" notation, which forces 
# the script to execute under the current shell, instead of creating a new one.
. ./deploy-common.sh
```

That's it.  Now your _common_ infrastructure is setup and can be referenced when deploying instances of the SFTP solution.

### Add SFTP users to Key Vault

The users you add to the Key Vault represent the _SFTP users_ you want accounts created for in the underlying SFTP host running in ACI.  In other words, these are the user credentials you would later use to authenticate to your SFTP host using an FTP client such as FileZilla.  

> INFO: There is a very explicit format for the user credentials that you must follow when adding SFTP users to the Key Vault.  This requirement is because of the underlying [sshd](https://www.ssh.com/academy/ssh/sshd) process that will be running in the SFTP container image ([atmoz/sftp](https://hub.docker.com/r/atmoz/sftp)) on ACI.  If you're interested in learning more about this, explore the documentation [here](https://hub.docker.com/r/atmoz/sftp) to learn how the underlying system gets setup and the expected format of user credentials.

This solution requires that user credentials be formatted a specific way (see above).  The format for each SFTP user credential is `username:password`.  Since this solution leverages Azure Key Vault to store and manage these credentials, we are able to also "tag" (or group) users according to the SFTP deployment stamp/instance they will be using.  This means that when you are adding your SFTP users to Key Vault, you will also need to specify a _tag name_ and _tag value_.  By doing this, you can have multiple SFTP deployments in different regions, and the users that will be provisioned for each region will be determined by the _tag name_ and _tag value_ you assign to the user.

Below are expamples of how you can add users to the Key Vault.


```bash
# Add 2 users with an instance tag of 'eastus', meaning these users will use the SFTP deployment in East US.
# The `secret name` for user1 and user2 "user1cred" and "user2cred".  You can use different 'secret names' if you prefer.
# The value is the username:password (ie: credentials) for the user.
az keyvault secret set --vault-name $KV_NAME --name user1cred --value "user1:Password1" --tags instance="eastus"
az keyvault secret set --vault-name $KV_NAME --name user2cred --value "user2:Password2" --tags instance="eastus"

# Add 1 user with an instance tag of 'westus', meaning these users will use the SFTP deployment in West US.
az keyvault secret set --vault-name $KV_NAME --name user3cred --value "user3:Password3" --tags instance="westus"
```

### Deploy the SFTP Solution

This section of the documentation guides you through deploying the SFTP solution, which is, the SFTP host (sshd) process running on ACI.  The infrastructure includes an Azure File Share that the SFTP host will mount when it starts up.  This file share is where files uploaded by SFTP users will be stored.

> NOTE: You can deploy the SFTP solution as many times as you want (perhaps in different regions).  Each SFTP deployment/instance will leverage the _common_ resources you deployed previously.

> NOTE: If you closed your terminal shell session since deploying the _common_ resources, then re-run the `deploy-common.sh` script (see above) before proceeding.  The `deploy-common.sh` script sets some environment variables that the `deploy-sftp.sh` script expects.

To prepare for the deployment of the SFTP solution, add/update the environment variables listed below to the end of the same `.env` you created previously for the _common_ resources.

```bash
# SFTP Solution resoure group settings
SFTP_RG_NAME=sftp-eastus-rg                # Resource group name for the SFTP resources
SFTP_LOCATION=eastus                       # az account list-locations --query '[].name'

# SFTP user provisioning settings
KV_TAG_NAME=instance                       # Name of the tag to query for when retrieving user credentials from key vault.
                                           # Don't change this unless you used a different tag name when adding the users to key vault.

KV_TAG_VALUE=eastus                        # The value to filter KV_TAG_NAME on.  ie: only users whose tag value is 'eastus'
```

Next, execute the `deploy-sftp.sh` script.

```bash
# Source and export the environment variables
set -a  
source .env
set +a

# Deploy the SFTP resources.  Pay attention to the ". ./" notation, which forces 
# the script to execute under the current shell, instead of creating a new one.
. ./deploy-sftp.sh
```

> NOTE: Deployment will take about 2 minutes to complete.

That's it.  Now your SFTP solution is setup.

If you want to deploy another instance of the SFTP solution (perhaps in a different region), repeat this section with different values for `SFTP_RG_NAME`, `SFTP_LOCATION`, and `SFTP_TAG_VALUE` in your `.env` file.

Next, see how to use your SFTP solution from an FTP client application.

## Use an FTP client to backup files

Any FTP client capable of SFTP protocol can be used.

You will first need to retrieve the FQDN of your ACI deployed in the SFTP solution.  You can find this by navigating to the ACI Overview blade in the Azure portal.  This is the DNS name of your SFTP host that you will use when connecting to it from your FTP client. 

The example below shows how you can launch File Zilla for _user1_ as provisioned above.

```bash
# Launch File Zilla for user1
# Replace <HOST_DNS> with the FQDN of your ACI
filezilla sftp://user1:Password1@<HOST_DNS>:22
```