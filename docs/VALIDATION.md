# Validation status

This is an Alpha project. A passing build is not a claim that every launch service or OS version is safe to modify.

## Automated

45 core tests cover plist scanning, malformed and symbolic-link inputs, backup fingerprints, file ownership and modes, conflicting restoration, interrupted journals, loaded-source validation, inventory parsing and grouping, localization, exact service attribution, snapshot permissions, parked-item reconciliation, and read-host reuse / shutdown / timeout behavior.

Mutation tests use independent temporary directories and fake launch controllers. Read-host transport tests use harmless fixture processes and do not request administrator authentication.

CI is configured for Apple silicon on macOS 26 and Intel on macOS 15. See the actual workflow status for the latest result.

## Manually checked

On an Apple silicon development Mac: native list and settings, cancellation and snapshot behavior, inventory grouping against System Settings, reversible parking of a user-requested legacy user agent, parked-item visibility, and consecutive system reads with no second password prompt during the same short authorization session.

The interface and packaged application have been inspected locally. Public screenshots use fictional demo data.

## Still needed

Isolated runtime tests for full system-daemon parking and restoration, reboot and relogin scenarios, forced interruption, older macOS releases, Intel hardware, app updates that regenerate configurations, and system output changes. Touch ID availability is controlled by macOS and is not guaranteed.

Preview binaries are ad-hoc signed, not Developer ID signed or notarized. The original icon artwork is rendered from the committed Swift source.
