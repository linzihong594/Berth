# Contributing to Berth

Small, focused improvements are welcome. For changes to service mutation or authorization, open an issue describing the intended behavior before implementing a broad redesign.

## Local development

Use macOS 14+ with Swift 6+ and Xcode Command Line Tools. There are no third-party package dependencies.

```sh
./scripts/test.sh
./scripts/build-app.sh
```

Run the app in demo mode for screenshots. Keep real system inventories, user paths, configuration contents, passwords, and recovery archives out of commits and issues.

## Tests and boundaries

Write mutation tests using temporary directories and a fake `LaunchControlling` implementation. Do not unload or move your real services as an automated test. Keep cancelled reads non-destructive, preserve the previous snapshot, and never infer that an unknown record is safe to remove.

Changes must preserve backup integrity, no-overwrite restoration, ownership and permission checks, fixed privileged command boundaries, and explicit user-triggered authorization. Do not add private database writes, `resetbtm`, app-bundle modification, automatic privilege prompts, or arbitrary shell commands.

## Pull requests

Explain the user-visible problem, the resulting behavior, and how it was validated. Include before/after images for visible interface changes using fictional data. Keep unrelated refactors separate. If a macOS version or hardware architecture was not tested, say so.

Version strings come from `VERSION`. `scripts/draw-icon.swift` is the editable source of the original icon artwork. Update the changelog and relevant documentation when behavior changes.

## Reporting bugs

Use the issue template with macOS version, CPU architecture, app version, reproduction steps, and expected behavior. Redact private data. Security-sensitive reports belong in the private channel described in [SECURITY.md](SECURITY.md).
