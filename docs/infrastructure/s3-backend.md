# S3 Backend Setup — Hetzner Object Storage

OpenTofu/Terraform state storage using Hetzner Object Storage S3-compatible API.

## Backend Configuration

Configured in `resources/bootstrap/providers.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "homelab-prd"
    key    = "tofu/bootstrap.tfstate"

    region   = "nbg1"
    endpoint = "https://nbg1.your-objectstorage.com"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
  }
}
```

The gitops-config stack uses `key = "tofu/gitops-config.tfstate"` and additionally sets `use_path_style = true` and `skip_requesting_account_id = true`.

---

## Authentication

Credentials via **environment variables** (not stored in code):

```bash
export AWS_ACCESS_KEY_ID="your-hetzner-access-key"
export AWS_SECRET_ACCESS_KEY="your-hetzner-secret-key"
```

These are loaded via `scripts/load-secrets.sh` which pulls them from 1Password.

---

## Obtaining Hetzner Credentials

1. Log in to Hetzner Cloud Console
2. Navigate to **Object Storage** → **S3 Access Keys**
3. Create a new S3 Access Key:
   - Description: `terraform-state-backend`
   - Permissions: Read & Write
4. Copy **Access Key** → `AWS_ACCESS_KEY_ID`
5. Copy **Secret Key** → `AWS_SECRET_ACCESS_KEY`

> The secret key is only shown once. Store it securely in 1Password.

---

## Shell Configuration

Add to `~/.zshrc`:

```bash
export AWS_ACCESS_KEY_ID="<your-access-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret-key>"
```

Then reload: `source ~/.zshrc`

Or use 1Password CLI: `source resources/bootstrap/scripts/load-secrets.sh`

---

## Initialize Backend

```bash
cd resources/bootstrap
tofu init
```

---

## State Operations

```bash
# View current state
tofu state list

# Pull remote state locally
tofu state pull > local-state-backup.json

# Force unlock (if locked after crash)
tofu force-unlock <LOCK_ID>
```

---

## Multi-Environment Strategy

For a test cluster, use a separate state key:

```hcl
backend "s3" {
  bucket = "homelab-prd"
  key    = "tst/tofu/bootstrap.tfstate"
  # ... rest same
}
```

---

## Security Notes

- Credentials via environment variables (not in git)
- Backend config in git (no secrets in it)
- State file contains sensitive data → bucket is private
- Hetzner access key can be restricted via bucket policies
