# Security

Gyro's app installs a helper daemon that runs as root, so security problems matter
here even though the project is small.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through
[GitHub's security advisories](https://github.com/nathanielnoyd/gyro-mac/security/advisories/new)
instead, with steps to reproduce if you can. You'll get a reply within a week.

## What's in scope

- The helper daemon (`App/GyroHelper`) and the XPC interface it exposes (`Sources/GyroXPC`)
- Gesture actions, which can run shortcuts and shell scripts
- Anything else that lets one process or user do something it otherwise couldn't
