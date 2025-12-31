# Security Policy

## Supported Versions

We release security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.3.x   | :white_check_mark: |
| < 0.3   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in SecretManagement.Sops, please report it responsibly:

1. **Do not** disclose the vulnerability publicly until it has been addressed
2. Send details to the module maintainer via private communication channels
3. Include as much information as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt of your vulnerability report and work to validate and address the issue promptly.

## Security Best Practices

When using SecretManagement.Sops, follow these security best practices:

### Encryption Keys

- **Use strong encryption backends**: Prefer Azure Key Vault or age over PGP where possible
- **Rotate keys regularly**: Implement a key rotation policy for your encryption keys
- **Secure key storage**: Store age keys in secure locations with appropriate file permissions
- **Limit key access**: Grant minimum necessary permissions to encryption keys

### SOPS Configuration

- **Configure `.sops.yaml` properly**: Use `encrypted_regex` to encrypt only secret data, not metadata
  ```yaml
  creation_rules:
    - encrypted_regex: '^(data|stringData)$'  # For Kubernetes Secrets
  ```
- **Use path-based rules**: Configure different encryption keys for different environments
- **Audit access**: Monitor who has access to decrypt your secrets

### PowerShell Module Usage

- **Never commit unencrypted secrets**: Always encrypt secrets before committing to version control
- **Use `-AsPlainText` sparingly**: Only retrieve secrets as plain text when absolutely necessary
- **Secure your vault path**: Ensure the directory containing SOPS files has appropriate permissions
- **Validate vault registration**: Always test vault configuration with `Test-SecretVault`

### Kubernetes Secrets

- **Encrypt only secret data**: Configure SOPS to encrypt only `data` and `stringData` fields
- **Use namespace isolation**: Leverage Kubernetes namespaces for secret isolation
- **Implement RBAC**: Control who can access secrets in your Kubernetes cluster
- **Monitor secret access**: Enable audit logging for secret access in Kubernetes

### CI/CD Pipelines

- **Use service principals**: Authenticate with service principals, not user accounts
- **Limit permissions**: Grant only decrypt permissions, not encrypt/delete unless necessary
- **Rotate credentials**: Regularly rotate service principal credentials
- **Secure build agents**: Ensure build agents are properly secured and patched

## Known Security Considerations

### SOPS Binary Execution

This module executes the SOPS binary as an external process. Ensure:
- SOPS is obtained from official sources (https://github.com/getsops/sops/releases)
- The SOPS binary in your PATH is verified and trusted
- Your system PATH doesn't include untrusted directories

### Plain Text in Memory

When retrieving secrets with `-AsPlainText`, values are temporarily stored as plain text in PowerShell memory. Minimize exposure by:
- Using SecureString return type when possible (default behavior)
- Clearing variables containing plain text secrets after use
- Avoiding logging or displaying plain text secrets

### File System Permissions

SOPS-encrypted files are stored on disk. While encrypted, file permissions should still be appropriate:
- Limit read access to the vault directory
- Use proper ACLs on Windows or file permissions on Linux/macOS
- Monitor file access with auditing where available

## Acknowledgments

We appreciate responsible disclosure of security vulnerabilities. Contributors who report valid security issues will be acknowledged (with permission) in release notes.

## Updates

This security policy may be updated periodically. Check back regularly for the latest guidance.
