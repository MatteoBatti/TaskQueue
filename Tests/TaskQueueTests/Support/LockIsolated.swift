import Foundation

/// Thread-safe wrapper for shared mutable state in tests
final class LockIsolated<Value>: @unchecked Sendable {
    
    private let lock = NSRecursiveLock()
    private var _value: Value
    
    init(_ value: Value) {
        self._value = value
    }
    
    func update(_ transform: (inout Value) throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        try transform(&_value)
    }
    
    func value() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return self._value
    }
}