# Contributing

Thanks for helping out. The most useful contribution right now needs no code at all:
a [hardware report](https://github.com/nathanielnoyd/gyro-mac/issues/new?template=hardware-report.yml)
from a Mac that isn't an M5 Pro MacBook Pro, which is the only one gyro has been tested on.

## Building

You need macOS 26 and Xcode 26 or later.

```bash
swift build          # the gyro command and GyroKit
swift test           # unit tests; they use recorded and simulated motion, no sensors needed
sudo .build/debug/gyro
```

The app lives in `App/Gyro.xcodeproj`. See [The app](README.md#the-app) in the README for
signing and the privileged helper.

## Pull requests

- Keep each pull request to one change, and explain why it's needed as well as what it does.
- Add or update tests in `Tests/GyroKitTests` for changes to GyroKit. Motion can be
  synthesized (see `MotionEventTests.swift`) or recorded with
  `sudo gyro events --record` and replayed from `Tests/GyroKitTests/Fixtures`.
- Match the style of the surrounding code, and keep `swift build` free of warnings.
- Changes to gesture presets should say which Mac and surface the new ranges were measured on.
- CI builds the package, runs the tests and builds the app on every pull request.
