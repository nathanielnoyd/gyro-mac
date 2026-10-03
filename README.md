# gyro

Read the accelerometer, gyroscope and lid angle sensor hidden inside Apple Silicon MacBooks.

Apple doesn't offer a public API for these sensors. They sit behind the
**Sensor Processing Unit (SPU)**, the always-on coprocessor that also handles
lid and ambient-light sensing. `gyro` talks to them directly through IOKit.

```
  gyro  Mac17,9                                                ●  800 Hz

  ACCELERATION g                        ROTATION °/s
  x  ─────────┼━─────────  +0.021       x  ─────────┼──────────    -0.4
  y  ────────━┼──────────  -0.064       y  ─────────┼──────────    +0.2
  z  ─────────┼━━━━━─────  +0.997       z  ─────────┼──────────    +0.1

  ORIENTATION °                         LID °
  roll  ───────┼───────    -3.7         ━━━━━━━━━━━────────   105°
  pitch ───────┼───────    +1.2
  yaw   ───────┼───────    +0.0
```

## Requirements

- An Apple Silicon MacBook (tested on an M5 Pro MacBook Pro; reports from other models welcome)
- macOS 26 or later
- Swift 6.2 or later (Xcode 26+)

## Install

```bash
git clone https://github.com/nathanielnoyd/gyro-mac.git
cd gyro-mac
swift build -c release
cp .build/release/gyro /usr/local/bin/
```

## Usage

```bash
sudo gyro                      # live dashboard of every sensor
sudo gyro stream               # print readings as a table
sudo gyro stream -f csv -d 10 > motion.csv
sudo gyro stream -f json | jq .attitude
gyro lid --watch               # lid angle, no sudo needed
gyro sensors                   # list what this Mac has
```

The accelerometer and gyroscope only report to processes running as root.
Without `sudo`, the dashboard still shows the lid angle.

## How it works

Each SPU sensor is an `AppleSPUHIDDevice` in the I/O Registry, identified by its HID usage:

| Sensor        | Usage page | Usage | Format                                           |
| ------------- | ---------- | ----- | ------------------------------------------------ |
| Accelerometer | `0xFF00`   | `0x03` | 22-byte input report, x/y/z as 16.16 fixed point, in g |
| Gyroscope     | `0xFF00`   | `0x09` | Same layout, in degrees per second               |
| Lid angle     | `0x0020`   | `0x8A` | Feature report 1, `UInt16` degrees               |
| Ambient light | `0xFF00`   | `0x04` | Not decoded yet                                  |

To start the IMU, `gyro` sets `SensorPropertyReportingState`,
`SensorPropertyPowerState` and `ReportInterval` on the matching
`AppleSPUHIDDriver`. The driver only applies these for root. Readings
then arrive as HID input reports, about 800 per second from each sensor.

Orientation comes from a [Mahony complementary filter](Sources/GyroKit/Fusion/MahonyFilter.swift).
It integrates the gyroscope and uses gravity from the accelerometer to correct drift.
Pitch and roll are absolute. There's no magnetometer, so yaw drifts; press `z` in the dashboard to re-zero it.

## Using GyroKit in your own code

The sensor code lives in a separate library you can depend on:

```swift
import GyroKit

let angle = try LidAngleSensor().angle()

var tracker = MotionTracker()
for await sample in try MotionSensor().samples() {   // requires root
    tracker.process(sample)
    print(tracker.snapshot.attitude)
}
```

## Project layout

```
Sources/GyroKit/     Sensor access, report decoding and sensor fusion
  IOKit/             Thin wrappers over IOHIDDevice and the I/O Registry
  Sensors/           MotionSensor, LidAngleSensor, SPUSensor
  Fusion/            MahonyFilter, MotionTracker
  Math/              Vector3, Quaternion, Attitude
Sources/gyro/        The command-line tool
Tests/GyroKitTests/  Unit tests for decoding and fusion
```

## Caveats

These are undocumented interfaces discovered through reverse engineering.
They may change or disappear in any macOS update. Use at your own risk.

## Credits

- [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) worked out the SPU IMU report format.
- [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) found the lid angle sensor.

## License

[MIT](LICENSE)
