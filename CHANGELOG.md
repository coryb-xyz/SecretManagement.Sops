# Changelog

All notable changes to SecretManagement.Sops will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2025-01-30

### Added
- **Full read/write support**: Complete implementation of Set-Secret and Remove-Secret
- **Kubernetes Secret support**: Automatic detection and parsing of Kubernetes Secret manifests
- **Namespace support**: Folder-based namespacing with collision detection
- **Data key extraction**: Access individual keys from Kubernetes Secrets using `secret-name/data-key` syntax
- **Multiple naming strategies**: RelativePath (default), FileName, and KubernetesMetadata
- **PSCredential auto-conversion**: Automatic conversion for secrets with username/password fields
- **Multi-backend support**: Azure Key Vault, age, AWS KMS, GCP KMS, and PGP encryption
- **Patch-first approach**: Set-Secret preserves file structure and comments when updating existing files
- **Comprehensive error handling**: Detailed error messages with troubleshooting guidance
- **Cross-platform support**: Works on Windows, Linux, and macOS with PowerShell 5.1+

### Changed
- Module version bumped from 0.1.0 to 0.3.0 to reflect feature completeness
- Documentation updated to accurately reflect full capabilities
- Removed outdated "read-only" and "Phase 1 MVP" references

### Fixed
- Documentation accuracy issues corrected

## [0.1.0] - 2025-01-15

### Added
- Initial implementation of SecretManagement extension vault for SOPS
- Get-Secret: Retrieve and decrypt SOPS-encrypted secrets
- Get-SecretInfo: List secrets with metadata and filtering
- Test-SecretVault: Validate vault configuration
- YAML format support
- Basic error handling and troubleshooting hints

### Known Limitations
- Read-only implementation (Set-Secret and Remove-Secret stubs only)
- YAML format only
- No caching
- No Unlock-SecretVault implementation
