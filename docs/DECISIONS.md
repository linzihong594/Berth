# Technical decisions

## Native, narrow scope

Berth uses SwiftUI / AppKit and Swift Package Manager without third-party dependencies. The main interface represents the system's background-activity groups; app-bundle discoveries and launch files are internal attribution evidence, not extra visible candidates. The interface follows system appearance.

## System inventory and authorization

An explicit read executes the fixed system command `/usr/bin/sfltool dumpbtm`. Its output is diagnostic rather than a stable API. Unknown formats fail visibly and preserve the previous snapshot. Parsing accepts LF, CR, and CRLF; AppleScript is instructed to preserve line endings.

The normal-user read host retains one fixed NSAppleScript instance so macOS can reuse short-lived authorization. It accepts only `read` through anonymous pipes, returns bounded JSON, has a 60-second deadline, and exits on app shutdown, explicit session close, or five minutes of inactivity. It is not an installed daemon. Whether another prompt or Touch ID is available is determined by macOS. No passwords or authorization policies are stored or changed.

The snapshot directory is user-owned and private (0700); the snapshot file is 0600. Only required fields are cached. Startup and local refresh never prompt for authorization.

## Grouping and attribution

Prefer the current user's record, then global and root records when deduplicating. Group app and developer roots with their internal members. Helper components do not become unrelated extra rows. Localized display names come from preferred InfoPlist resources.

Exact system parent-child identifiers and configuration paths take precedence over signing metadata. Two services signed by the same developer can belong to different visible groups. Signing metadata explains origin; it is not a trust-validation claim. Only an unambiguous supported service receives a mutation action.

## Reversible parking

Re-read the source label and SHA-256 before acting, validate file type / ownership / mode / directory, and verify the source of any loaded job. Write the original backup and prepared journal before unloading and moving the configuration. Protect operations with a directory lock.

Restoration refuses to overwrite a different file, preserves original attributes, and loads only jobs that were loaded before parking. Original backups remain after restoration. Incomplete journals can resume. Completed parked records hide matching cached activity groups only if no relevant configuration has reappeared and no other group service remains installed.

The privileged tool runs only on demand and requires root. Its accepted operations and source / archive directories are fixed. Root-owned manifests remain the authority for system restoration; user-visible receipt copies are not trusted authorization data. Shared LaunchAgents and app-bundle components remain read-only.

## Public release

The public repository starts with a sanitized source snapshot; local session notes, raw inventories, and private development history are not published. Images use fictional demonstration data. The code and original icon artwork use the MIT license. Alpha packages are ad-hoc signed and architecture-specific; stable distribution requires further runtime validation, signing, notarization, and independent review.

## References

- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Authorization Services](https://developer.apple.com/documentation/security/authorization-services)
- [AppleScript command reference](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html)
- [Apple background task management](https://support.apple.com/guide/deployment/depdca572563/web)
