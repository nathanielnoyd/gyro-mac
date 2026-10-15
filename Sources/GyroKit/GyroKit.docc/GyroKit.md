# ``GyroKit``

Read the motion and lid angle sensors built into Apple Silicon MacBooks.

## Overview

Apple Silicon MacBooks have an accelerometer, a gyroscope and a lid angle sensor attached to the
Sensor Processing Unit (SPU). macOS has no public API for them, so GyroKit reads them directly
through IOKit. The report formats come from reverse engineering and may change between macOS
releases.

The accelerometer and gyroscope only stream data to processes running as root. The lid angle
sensor works for any process.

On top of the raw readings, GyroKit estimates the Mac's orientation, detects taps and ongoing
motion such as typing, and recognizes gestures from them.

```swift
import GyroKit

let angle = try LidAngleSensor().angle()

var tracker = MotionTracker()
for await sample in try MotionSensor().samples() {   // requires root
    tracker.process(sample)
    print(tracker.snapshot.attitude)
}
```

## Topics

### Sensors

- ``MotionSensor``
- ``MotionSample``
- ``LidAngleSensor``
- ``LidPosition``
- ``SPUSensor``
- ``SimulatedMotion``

### Orientation

- ``MotionTracker``
- ``MotionSnapshot``
- ``MahonyFilter``
- ``GyroBiasEstimator``
- ``VibrationMeter``
- ``SampleRateMeter``

### Motion events and gestures

- ``MotionEventDetector``
- ``MotionEvent``
- ``MotionFeature``
- ``GestureSignature``
- ``GestureRecognizer``
- ``GesturePreset``

### Recordings

- ``MotionRecording``
- ``GestureCalibration``

### Math

- ``Vector3``
- ``Quaternion``
- ``Attitude``

### Errors

- ``GyroError``
