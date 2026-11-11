# Berth development conventions

- Native SwiftUI / AppKit, macOS 14+, Swift 6+, no third-party dependencies.
- Keep the product focused on system background activities, source inspection, reversible parking, and restoration.
- Use temporary directories and fake launch controllers for mutation tests. Never alter real services just to verify development.
- Do not call resetbtm, edit private BTM databases, modify app-bundle components, or write to /System.
- Keep original backups verifiable. Restoration must not overwrite a different existing file.
- Preserve ownership, file-type, source-path, permission, and content-fingerprint checks.
- Privileged service commands and the read host accept fixed requests only; no arbitrary shell text or paths.
- Authorization must follow an explicit user action. Do not queue automatic retries or trigger authentication during startup or local refresh. Preserve old results on cancellation, failure, or timeout.
- Never commit raw system inventories, personal paths, credentials, or recovery archives. Use fictional demo data for screenshots.
- Update docs/PLAN.md before adding features. Run scripts/test.sh and build the app for code changes; record relevant limits in docs/VALIDATION.md.
- Publish or push only when explicitly requested by the maintainer. Keep versioning in VERSION.
