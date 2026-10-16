import Foundation
import IOKit

/// Low-level access to the Apple System Management Controller (AppleSMC user client).
///
/// Reading works for any user. Writing (fan mode / target speed) requires root,
/// which is why writes are done by the privileged helper `fancontrold`.
public final class SMC {
    public enum SMCError: Error, CustomStringConvertible {
        case serviceNotFound
        case openFailed(kern_return_t)
        case callFailed(kern_return_t)
        case smcResult(UInt8, key: String)
        case badKey(String)
        case badData(String)

        public var description: String {
            switch self {
            case .serviceNotFound: return "AppleSMC service not found"
            case .openFailed(let kr): return "IOServiceOpen failed: \(kr)"
            case .callFailed(let kr): return "IOConnectCallStructMethod failed: \(String(format: "0x%08x", kr))"
            case .smcResult(let r, let key): return "SMC returned \(r) for key \(key)"
            case .badKey(let k): return "Bad SMC key: \(k)"
            case .badData(let k): return "Unexpected data for key \(k)"
            }
        }
    }

    public struct KeyInfo {
        public let size: UInt32
        public let type: String
    }

    public struct Value {
        public let key: String
        public let type: String
        public let bytes: [UInt8]

        /// Decodes the common numeric SMC data types to Double.
        public var double: Double? {
            switch type {
            case "flt ":
                guard bytes.count >= 4 else { return nil }
                let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
                return Double(Float(bitPattern: bits))
            case "fpe2":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
            case "sp78":
                guard bytes.count >= 2 else { return nil }
                return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
            case "ui8 ", "flag":
                guard bytes.count >= 1 else { return nil }
                return Double(bytes[0])
            case "ui16":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            case "ui32":
                guard bytes.count >= 4 else { return nil }
                return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
            default:
                return nil
            }
        }
    }

    // Selector and commands of the AppleSMC user client.
    private static let kernelIndexSMC: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdWriteBytes: UInt8 = 6
    private static let cmdReadIndex: UInt8 = 8
    private static let cmdReadKeyInfo: UInt8 = 9

    // Layout of SMCKeyData_t (80 bytes), offsets in bytes.
    private static let structSize = 80
    private static let offKey = 0
    private static let offInfoSize = 28
    private static let offInfoType = 32
    private static let offResult = 40
    private static let offData8 = 42
    private static let offData32 = 44
    private static let offBytes = 48

    private var connection: io_connect_t = 0
    private var infoCache: [String: KeyInfo] = [:]
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public API

    public func keyInfo(_ key: String) throws -> KeyInfo {
        lock.lock(); defer { lock.unlock() }
        return try keyInfoLocked(key)
    }

    public func read(_ key: String) throws -> Value {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        var input = [UInt8](repeating: 0, count: Self.structSize)
        try Self.put(fourCC: key, into: &input, at: Self.offKey)
        Self.put(u32: info.size, into: &input, at: Self.offInfoSize)
        input[Self.offData8] = Self.cmdReadBytes
        let output = try call(input, key: key)
        let count = min(Int(info.size), 32)
        return Value(key: key, type: info.type, bytes: Array(output[Self.offBytes..<(Self.offBytes + count)]))
    }

    public func readDouble(_ key: String) -> Double? {
        (try? read(key))?.double
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        guard bytes.count == Int(info.size) else { throw SMCError.badData(key) }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        try Self.put(fourCC: key, into: &input, at: Self.offKey)
        Self.put(u32: info.size, into: &input, at: Self.offInfoSize)
        input[Self.offData8] = Self.cmdWriteBytes
        for (i, b) in bytes.enumerated() { input[Self.offBytes + i] = b }
        _ = try call(input, key: key)
    }

    /// Writes a numeric value, encoding it according to the key's SMC data type.
    public func write(_ key: String, value: Double) throws {
        let info = try keyInfo(key)
        let bytes: [UInt8]
        switch info.type {
        case "flt ":
            let bits = Float(value).bitPattern
            bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
        case "fpe2":
            let v = UInt16(max(0, min(16383, value)) * 4)
            bytes = [UInt8(v >> 8), UInt8(v & 0xff)]
        case "ui8 ", "flag":
            bytes = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let v = UInt16(max(0, min(65535, value)))
            bytes = [UInt8(v >> 8), UInt8(v & 0xff)]
        default:
            throw SMCError.badData(key)
        }
        try write(key, bytes: bytes)
    }

    public func hasKey(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    /// Enumerates every key the SMC exposes.
    public func allKeys() -> [String] {
        guard let count = readDouble("#KEY") else { return [] }
        lock.lock(); defer { lock.unlock() }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for i in 0..<UInt32(count) {
            var input = [UInt8](repeating: 0, count: Self.structSize)
            input[Self.offData8] = Self.cmdReadIndex
            Self.put(u32: i, into: &input, at: Self.offData32)
            guard let output = try? call(input, key: "#\(i)") else { continue }
            keys.append(Self.fourCC(from: output, at: Self.offKey))
        }
        return keys
    }

    // MARK: - Internals

    private func keyInfoLocked(_ key: String) throws -> KeyInfo {
        if let cached = infoCache[key] { return cached }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        try Self.put(fourCC: key, into: &input, at: Self.offKey)
        input[Self.offData8] = Self.cmdReadKeyInfo
        let output = try call(input, key: key)
        let size = Self.u32(from: output, at: Self.offInfoSize)
        let type = Self.fourCC(from: output, at: Self.offInfoType)
        let info = KeyInfo(size: size, type: type)
        infoCache[key] = info
        return info
    }

    private func call(_ input: [UInt8], key: String) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outSize = Self.structSize
        let kr = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, Self.kernelIndexSMC,
                                          inPtr.baseAddress, Self.structSize,
                                          outPtr.baseAddress, &outSize)
            }
        }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        let result = output[Self.offResult]
        guard result == 0 else { throw SMCError.smcResult(result, key: key) }
        return output
    }

    // Integers inside SMCKeyData_t are in host (little-endian) order.
    private static func put(u32 value: UInt32, into buf: inout [UInt8], at offset: Int) {
        buf[offset] = UInt8(value & 0xff)
        buf[offset + 1] = UInt8(value >> 8 & 0xff)
        buf[offset + 2] = UInt8(value >> 16 & 0xff)
        buf[offset + 3] = UInt8(value >> 24 & 0xff)
    }

    private static func u32(from buf: [UInt8], at offset: Int) -> UInt32 {
        UInt32(buf[offset]) | UInt32(buf[offset + 1]) << 8 | UInt32(buf[offset + 2]) << 16 | UInt32(buf[offset + 3]) << 24
    }

    private static func put(fourCC key: String, into buf: inout [UInt8], at offset: Int) throws {
        let chars = Array(key.utf8)
        guard chars.count == 4 else { throw SMCError.badKey(key) }
        let value = UInt32(chars[0]) << 24 | UInt32(chars[1]) << 16 | UInt32(chars[2]) << 8 | UInt32(chars[3])
        put(u32: value, into: &buf, at: offset)
    }

    private static func fourCC(from buf: [UInt8], at offset: Int) -> String {
        let v = u32(from: buf, at: offset)
        let bytes = [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
