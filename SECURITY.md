# Security Policy

## Supported versions

iContainer is a hobby project; only the latest released version is supported.
Please make sure you're on the most recent
[release](https://github.com/nico81/iContainer/releases) before reporting.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting instead:

1. Go to the [Security tab](https://github.com/nico81/iContainer/security)
   of the repository.
2. Click **Report a vulnerability**.
3. Describe the issue, the affected version, and steps to reproduce.

This keeps the report private until a fix is available. As this is a
best-effort hobby project, response times aren't guaranteed — but reports are
taken seriously and very much appreciated.

## Scope notes

iContainer is a GUI on top of the official Apple `container` CLI. It runs the
CLI as a subprocess and can handle registry credentials via that CLI.
Vulnerabilities in the `container` CLI or daemon itself should be reported
upstream at [apple/container](https://github.com/apple/container).
