#!/bin/bash
# Generate all input-files from 1Password for GitOps bootstrap
# Usage: ./scripts/generate-input-files.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if 1Password CLI is installed
if ! command -v op &> /dev/null; then
    echo -e "${RED}❌ Error: 1Password CLI (op) is not installed${NC}"
    echo "Install from: https://developer.1password.com/docs/cli/get-started/"
    exit 1
fi

# Check if user is signed in
if ! op whoami &> /dev/null; then
    echo -e "${RED}❌ Please sign in to 1Password first:${NC}"
    echo "  eval \$(op signin)"
    exit 1
fi

# Create input-files directory if it doesn't exist
mkdir -p input-files

echo -e "${GREEN}🔐 Generating input-files from 1Password...${NC}"
echo ""

##############################################
# 1. Generate secret.yaml (1Password Connect credentials)
##############################################
echo -e "${BLUE}  [1/5] Generating secret.yaml...${NC}"

# Get 1Password Connect credentials (base64 encoded JSON)
ONEPASSWORD_CREDENTIALS=$(op read "op://KubernetesSecrets/onepassword-connect-credentials.json/password" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Error loading 1Password Connect credentials${NC}"
    echo "Expected: op://KubernetesSecrets/onepassword-connect-credentials.json/password"
    exit 1
fi

# Get 1Password Connect token
ONEPASSWORD_TOKEN=$(op read "op://KubernetesSecrets/onepassword-connect-token/password" 2>&1 | tr -d '\n\r')
if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Error loading 1Password Connect token${NC}"
    echo "Expected: op://KubernetesSecrets/onepassword-connect-token/password"
    exit 1
fi

# Generate secret.yaml
cat > input-files/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-credentials
  namespace: onepassword
type: Opaque
stringData:
  # NOTE: This secret value must be base64 encoded after it becomes the OP_SESSION env var in the Connect Server Deployment, that means double base64 encoded here. (Or single w/ stringData.)
  onepassword-connect-credentials.json: |-
    ${ONEPASSWORD_CREDENTIALS}
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-token-external-secret
  namespace: external-secrets
type: Opaque
stringData:
  onepassword-connect-token: ${ONEPASSWORD_TOKEN}
EOF

echo -e "${GREEN}  ✓ Created input-files/secret.yaml${NC}"

##############################################
# 2. Generate github-client-secret.yaml (GitHub OAuth for ArgoCD SSO)
##############################################
echo -e "${BLUE}  [2/5] Generating github-client-secret.yaml...${NC}"

cat > input-files/github-client-secret.yaml <<'EOF'
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-client-secret
  namespace: argocd
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    creationPolicy: Owner
    name: github-client-secret
    template:
      engineVersion: v2
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: argocd
          app.kubernetes.io/part-of: argocd
      data:
        dex.github.clientSecret: '{{ .clientSecret }}'
  data:
  - secretKey: clientSecret
    remoteRef:
      key: github-client-secrets
      property: password
EOF

echo -e "${GREEN}  ✓ Created input-files/github-client-secret.yaml${NC}"

##############################################
# 3. Generate github-private-repo-creds.yaml (GitHub App for private repos)
##############################################
echo -e "${BLUE}  [3/5] Generating github-private-repo-creds.yaml...${NC}"

cat > input-files/github-private-repo-creds.yaml <<'EOF'
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-private-config-creds
  namespace: argocd
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    creationPolicy: Owner
    name: github-private-config-creds
    template:
      engineVersion: v2
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: https://github.com/TheIronRock95/homelab-config.git
        name: github-private-config-creds
        githubAppID: "1225477"
        githubAppInstallationID: "65046796"
        githubAppPrivateKey: '{{ .argoPrivateKey }}'
  data:
  - secretKey: argoPrivateKey
    remoteRef:
      key: github-argo-app
      property: argocd-private-acces.2025-04-22.private-key.pem
EOF

echo -e "${GREEN}  ✓ Created input-files/github-private-repo-creds.yaml${NC}"

##############################################
# 4. Generate onepassword-connect-credentials.yaml (ESO refresh)
##############################################
echo -e "${BLUE}  [4/5] Generating onepassword-connect-credentials.yaml...${NC}"

cat > input-files/onepassword-connect-credentials.yaml <<'EOF'
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: onepassword-connect-credentials
  namespace: onepassword
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    creationPolicy: Owner
    name: onepassword-connect-credentials
    template:
      engineVersion: v2
      type: Opaque
      data:
        onepassword-connect-credentials.json: '{{ .credentials }}'
  data:
  - secretKey: credentials
    remoteRef:
      key: onepassword-connect-credentials.json
      property: password
EOF

echo -e "${GREEN}  ✓ Created input-files/onepassword-connect-credentials.yaml${NC}"

##############################################
# 5. Generate longhorn-s3-secret.yaml (Longhorn S3 backup credentials)
##############################################
echo -e "${BLUE}  [5/5] Generating longhorn-s3-secret.yaml...${NC}"

cat > input-files/longhorn-s3-secret.yaml <<'EOF'
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: longhorn-s3-backup-credentials
  namespace: longhorn-system
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    creationPolicy: Owner
    name: longhorn-s3-secret
    template:
      engineVersion: v2
      type: Opaque
      data:
        AWS_ACCESS_KEY_ID: '{{ .awsAccessKeyId }}'
        AWS_SECRET_ACCESS_KEY: '{{ .awsSecretAccessKey }}'
        AWS_ENDPOINTS: '{{ .awsEndpoints }}'
  data:
  - secretKey: awsAccessKeyId
    remoteRef:
      key: longhorn-s3-backup
      property: AWS_ACCESS_KEY_ID
  - secretKey: awsSecretAccessKey
    remoteRef:
      key: longhorn-s3-backup
      property: AWS_SECRET_ACCESS_KEY
  - secretKey: awsEndpoints
    remoteRef:
      key: longhorn-s3-backup
      property: AWS_ENDPOINTS
EOF

echo -e "${GREEN}  ✓ Created input-files/longhorn-s3-secret.yaml${NC}"

##############################################
# Summary
##############################################
echo ""
echo -e "${GREEN}✅ All input-files generated successfully!${NC}"
echo ""
echo "Generated files:"
echo "  ✓ input-files/secret.yaml"
echo "  ✓ input-files/github-client-secret.yaml"
echo "  ✓ input-files/github-private-repo-creds.yaml"
echo "  ✓ input-files/onepassword-connect-credentials.yaml"
echo "  ✓ input-files/longhorn-s3-secret.yaml"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: These files contain sensitive data!${NC}"
echo "  - They are automatically gitignored"
echo "  - Never commit them to version control"
echo "  - Regenerate them when needed with this script"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Load S3 credentials: ${BLUE}source ./scripts/load-secrets.sh${NC}"
echo "  2. Initialize Terraform: ${BLUE}tofu init${NC}"
echo "  3. Deploy GitOps stack: ${BLUE}tofu apply${NC}"
