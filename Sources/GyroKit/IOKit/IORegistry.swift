import IOKit

/// Small helpers for walking and editing the I/O Registry.
enum IORegistry {
    /// Calls `body` with every registered service of the given IOKit class.
    ///
    /// Each service is released after `body` returns, so don't keep it.
    /// Return `false` from `body` to stop early.
    static func forEachService(
        ofClass className: String,
        _ body: (io_service_t) throws -> Bool
    ) rethrows {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
                == kIOReturnSuccess
        else {
            return
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard try body(service) else { return }
        }
    }

    static func property<Value>(_ key: String, of entry: io_registry_entry_t, as _: Value.Type = Value.self) -> Value? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Value
    }

    static func setProperty(_ value: Int, forKey key: String, of entry: io_registry_entry_t) throws(GyroError) {
        try ioCheck(
            IORegistryEntrySetCFProperty(entry, key as CFString, value as CFNumber),
            "Setting \(key)"
        )
    }
}
