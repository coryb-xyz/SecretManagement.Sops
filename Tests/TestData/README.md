# Test Data Setup

This directory contains test data for SecretManagement.Sops testing.

## Prerequisites

Before running tests, you need to:

1. Install SOPS: https://github.com/getsops/sops/releases
2. Install age: https://github.com/FiloSottile/age/releases

## Setup Instructions

### 1. Generate age key

```bash
age-keygen -o test-key.txt
```

This will create a file like:
```
# created: 2025-01-15T10:30:00Z
# public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AGE-SECRET-KEY-1YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

### 2. Extract the public key

The public key is in the comment on line 2 (starts with `age1...`). Save this for the next step.

### 3. Create .sops.yaml configuration

Create a `.sops.yaml` file in this directory with the age public key:

```yaml
creation_rules:
  - path_regex: \.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Replace the `age1...` value with your actual public key from step 2.

### 4. Encrypt the test files

```bash
# Set the age key file environment variable
export SOPS_AGE_KEY_FILE=./test-key.txt

# Encrypt the test files
sops --encrypt simple-secret-plain.yaml > simple-secret.yaml
sops --encrypt k8s-secret-plain.yaml > k8s-secret.yaml
sops --encrypt credentials-plain.yaml > credentials.yaml
```

On Windows PowerShell:
```powershell
$env:SOPS_AGE_KEY_FILE = ".\test-key.txt"

sops --encrypt simple-secret-plain.yaml | Out-File -Encoding utf8 simple-secret.yaml
sops --encrypt k8s-secret-plain.yaml | Out-File -Encoding utf8 k8s-secret.yaml
sops --encrypt credentials-plain.yaml | Out-File -Encoding utf8 credentials.yaml
```

### 5. Verify encryption

Check that the files are encrypted:

```bash
cat simple-secret.yaml
```

You should see SOPS metadata like:
```yaml
database_host: ENC[AES256_GCM,data:...
database_port: ENC[AES256_GCM,data:...
...
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1...
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
```

### 6. Test decryption

```bash
sops --decrypt simple-secret.yaml
```

Should output the original unencrypted content.

## Files

### Plain (unencrypted) files
- `simple-secret-plain.yaml` - Simple key-value secret
- `k8s-secret-plain.yaml` - Kubernetes Secret manifest
- `credentials-plain.yaml` - Username/password for PSCredential testing

### Encrypted files (created by setup)
- `simple-secret.yaml` - SOPS-encrypted simple secret
- `k8s-secret.yaml` - SOPS-encrypted Kubernetes Secret
- `credentials.yaml` - SOPS-encrypted credentials

### Configuration
- `.sops.yaml` - SOPS configuration (created by setup)
- `test-key.txt` - age private key (created by setup, **DO NOT COMMIT**)

## Running Tests

Before running Pester tests, ensure:

1. The encrypted files exist (follow setup above)
2. `SOPS_AGE_KEY_FILE` environment variable is set to the test key file path:

```powershell
$env:SOPS_AGE_KEY_FILE = "C:\git\sops-vault\Tests\TestData\test-key.txt"
Invoke-Pester -Path ..\SecretManagement.Sops.Tests.ps1
```

## Security Notes

- The `test-key.txt` file should **NEVER** be committed to version control
- Add `test-key.txt` to `.gitignore`
- The plain text test files are intentionally included for setup convenience
- In production, never commit unencrypted secrets
