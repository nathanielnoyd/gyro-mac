import Dispatch
import IOKit.hid
import Synchronization

/// A minimal Swift wrapper around `IOHIDDevice`.
///
/// Supports the two things GyroKit needs: reading feature reports on demand,
/// and receiving a stream of input reports on a private dispatch queue.
final class HIDDevice: Sendable {
    /// Receives one input report. The buffer is only valid for the duration of the call.
    typealias ReportHandler = @Sendable (_ report: UnsafeRawBufferPointer, _ machTimestamp: UInt64) -> Void

    private enum State {
        case closed, open, streaming, cancelled
    }

    private nonisolated(unsafe) let device: IOHIDDevice
    private let queue: DispatchQueue
    private let state = Mutex(State.closed)

    init?(service: io_service_t, label: String) {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return nil }
        self.device = device
        self.queue = DispatchQueue(label: "GyroKit.HIDDevice.\(label)", qos: .userInteractive)
    }

    deinit {
        if state.withLock({ $0 == .open }) {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func open() throws(GyroError) {
        try state.withLock { state throws(GyroError) in
            guard state == .closed else { return }
            try ioCheck(IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)), "Opening HID device")
            state = .open
        }
    }

    func featureReport(id: Int, length: Int) throws(GyroError) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)
        try ioCheck(
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &report, &reportLength),
            "Reading HID feature report"
        )
        return Array(report.prefix(reportLength))
    }

    /// Starts delivering input reports to `handler` until ``cancel()`` is called.
    ///
    /// The device keeps itself alive while streaming, so callers may drop
    /// their reference without leaking the callback context.
    func startInputReports(maxLength: Int, handler: @escaping ReportHandler) throws(GyroError) {
        try open()
        let starting = state.withLock { state in
            guard state == .open else { return false }
            state = .streaming
            return true
        }
        // Already streaming, or cancelled.
        guard starting else { return }

        let context = ReportContext(handler: handler, maxLength: maxLength)
        let retainedContext = Unmanaged.passRetained(context)

        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device, context.buffer, maxLength,
            { context, _, _, _, _, report, length, timestamp in
                guard let context else { return }
                let reportContext = Unmanaged<ReportContext>.fromOpaque(context).takeUnretainedValue()
                reportContext.handler(UnsafeRawBufferPointer(start: report, count: length), timestamp)
            },
            retainedContext.toOpaque()
        )
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceSetCancelHandler(device) { [device] in
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            retainedContext.release()
        }
        IOHIDDeviceActivate(device)
    }

    /// Stops input report delivery and closes the device. Safe to call more than once.
    func cancel() {
        let wasStreaming = state.withLock { state in
            defer { state = .cancelled }
            return state == .streaming
        }
        if wasStreaming {
            IOHIDDeviceCancel(device)
        }
    }
}

/// Owns the report buffer and handler for the lifetime of an input report stream.
private final class ReportContext {
    let handler: HIDDevice.ReportHandler
    let buffer: UnsafeMutablePointer<UInt8>

    init(handler: @escaping HIDDevice.ReportHandler, maxLength: Int) {
        self.handler = handler
        self.buffer = .allocate(capacity: maxLength)
    }

    deinit {
        buffer.deallocate()
    }
}
