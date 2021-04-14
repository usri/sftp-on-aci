#!/bin/bash -e

usage() { echo "Usage: $0 <-k key-vault-name> <-t tag-name> <-v tag-value>"; }

while getopts "k:t:v:" opt; do
    case $opt in
        k)
            KV_NAME=$OPTARG  # [Required] -- Name of the Key Vault where user creds (secrets) are stored.
        ;;
        t)
            TAG_NAME=$OPTARG # [Required] -- Name of tag that will be used to query for secrets in the Key Vault.
        ;;
        v)
            TAG_VALUE=$OPTARG  # [Optional] -- Value for TAG_NAME to query for.
        ;;
        \?)
            usage
            exit 1
        ;;
    esac
done

# Check to make sure we have all the arguments that we need...
[[ -z $KV_NAME || -z $TAG_NAME || -z $TAG_VALUE ]] && { usage; exit 1; }

# Query key vault for a list of secrets (ids) 
VAULT_IDS=$(az keyvault secret list --vault-name $KV_NAME --query "[?tags.$TAG_NAME=='$TAG_VALUE']".id --output tsv)

# Retrieve the value (user credentials) for each secret and construct
# a string that contains each user's credentials.  This string is used
# later as the SFTP_USERS environment variable expected by 'sshd'.
SFTP_USERS=""
SFTP_USER_CREDS=""
SFTP_USER_GID=1001
SFTP_USER_COUNT=0

for VAULT_ID in $VAULT_IDS; do
    SECRET_VALUE=$(az keyvault secret show --id "$VAULT_ID" --query value --output tsv)
    SFTP_USER_CREDS="$SFTP_USER_CREDS $SECRET_VALUE:$SFTP_USER_GID"

    # Build an array of just the user names
    SFTP_USER=$(cut -d: -f1 <<< $SECRET_VALUE)
    if [ -z $SFTP_USERS ]
    then 
        SFTP_USERS="\"$SFTP_USER\""
    else 
        SFTP_USERS="$SFTP_USERS, \"$SFTP_USER\""
    fi

    ((++SFTP_USER_GID))
    ((++SFTP_USER_COUNT))
done

echo "{ \"sftp_user_count\" : $SFTP_USER_COUNT, \"sftp_users\" : [ $SFTP_USERS ], \"sftp_user_creds\" : \"$SFTP_USER_CREDS\" }"