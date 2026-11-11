# Security policy

Berth is an Alpha utility that can change launch configurations after an explicit user action. The latest Alpha is the only actively maintained preview; older previews may not receive fixes.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/linzihong594/Berth/security/advisories/new). Do not publish a proof of concept that affects real services, raw background-task output, personal file paths, authentication data, or recovery archives in a public issue. Include a minimal synthetic reproduction where possible.

If private reporting is unavailable, open an issue containing only a request for a private contact channel, without vulnerability details. There is no guaranteed response time or paid bounty program.

## Boundaries

The normal app does not run as root. The read host accepts only a fixed read request; the service tool accepts a small fixed command set and protected paths. Every service mutation validates source content and the recovery journal. No password is stored and no authorization policy, sudoers, or PAM configuration is modified.

These checks reduce common mistakes and path-confusion risks. They do not promise protection against every malicious process running as the same user, or constitute an independent security audit. Formal signing, notarization, broader runtime coverage, and additional review remain planned work.
