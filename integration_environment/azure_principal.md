# How to Create Azure App Principal

This guide documents how to create an AzureAD App Registration to test out Exchange Online connections.

## Steps

Run the following commands to create the principal with both a certificate and secret.

```bash
# Make sure we are in the `integration_environment` folder
cd integration_environment

# Run it in this container to access azure-cli
docker run -it -v "$( pwd ):/app:Z" -w /app mcr.microsoft.com/azure-cli

# Open the link and authenticate with a user with an O365 subscription
# Note: This requires some manual interaction
az login --allow-no-subscriptions

APP_NAME=omi-test
TENANT_ID="$( az account list --query [].tenantId -o tsv )"
PASSWORD="$( date +%s | sha256sum | base64 | head -c 32 ; echo )"

# Create the self signed cert
openssl req -x509 \
    -newkey rsa:2048 \
    -keyout exchange-key.pem \
    -passout "pass:${PASSWORD}" \
    -out exchange-cert.pem \
    -days 1 \
    -subj "/CN=ExchangeTest"

openssl pkcs12 -export \
    -out exchange-cert.pfx \
    -passout "pass:${PASSWORD}" \
    -inkey exchange-key.pem \
    -passin "pass:${PASSWORD}" \
    -in exchange-cert.pem

# Ensure other users have read access to our temp cert
chmod 644 exchange-cert.pfx

# We don't need the PEM key as Windows uses the PFX
rm exchange-key.pem

cat > exchange-manifest.json << EOL
[
  {
    "resourceAppId": "00000002-0000-0ff1-ce00-000000000000",
    "resourceAccess": [
      {
        "id": "dc50a0fb-09a3-484d-be87-e023b12c6440",
        "type": "Role"
      }
    ]
  },
  {
    "resourceAppId": "00000003-0000-0000-c000-000000000000",
    "resourceAccess": [
      {
        "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
        "type": "Scope"
      }
    ]
  }
]
EOL

az ad app create \
    --display-name "${APP_NAME}" \
    --oauth2-allow-implicit-flow false \
    --required-resource-accesses @exchange-manifest.json
rm exchange-manifest.json

APP_ID="$(az ad app list --display-name "${APP_NAME}" --query [].appId -o tsv)"

# Create the service principal for the app registration
az ad sp create \
    --id "${APP_ID}"

# Consent to the required resources the app registration has asked for
az ad app permission admin-consent \
    --id "${APP_ID}"

# Set the secret
az ad app credential reset \
    --id "${APP_ID}" \
    --password "${PASSWORD}" \
    --credential-description "Test secret" \
    --cert @exchange-cert.pem \
    --append

# Set the certificate
az ad app credential reset \
    --id "${APP_ID}" \
    --cert @exchange-cert.pem \
    --append

# Once uploaded we no longer need the cert PEM
rm exchange-cert.pem

# Output the relevant info required for libmi.tests.ps1
echo "{\"tenant_id\": \"${TENANT_ID}\", \"client_id\": \"${APP_ID}\", \"client_secret\": \"${PASSWORD}\"}" > exchange.json
```

Unfortunately this next step must be done manually, I've been unable to get this working in the azure-cli for now.
Open up the Azure Portal for the subscription and go to AzureAD -> Roles and administrators.
Find the `Exchange administrator` role and assign the `omi-test` app.

When `libmi.tests.ps1` finds the `exchange.json` file it will test out a connection to Azure using the client secret.
If the `exchange-cert.pfx` file is also present it will also test out certificate based authentication to Exchange Online.
