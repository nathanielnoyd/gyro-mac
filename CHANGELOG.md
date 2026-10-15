# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-14

The first release.

### Added

- **GyroKit**, a library that reads the accelerometer, gyroscope and lid angle sensor
  behind the Sensor Processing Unit of Apple Silicon MacBooks, fuses them into an
  orientation with a Mahony filter, learns the gyroscope's bias at rest, and recognizes
  taps, typing and other gestures.
- **gyro**, a command-line tool with a live dashboard and the `stream`, `events`,
  `calibrate`, `lid` and `sensors` commands.
- **Gyro**, a SwiftUI app with a 3D model, an artificial horizon, live traces, a menu bar
  level, and gestures that can run sounds, notifications, shortcuts, URLs and scripts.
  Its privileged helper streams readings over XPC, and only to the Gyro app.

[Unreleased]: https://github.com/nathanielnoyd/gyro-mac/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nathanielnoyd/gyro-mac/releases/tag/v0.1.0
