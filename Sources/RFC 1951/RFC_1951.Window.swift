internal import Byte

extension RFC_1951 {

    @safe
    struct Window {
        private var base: UnsafeMutablePointer<Byte>
        private var capacity: Int
        private(set) var count: Int = 0

        init(capacity: Int) {
            let capacity = Swift.max(capacity, Self.slack)
            unsafe self.base = .allocate(capacity: capacity)
            self.capacity = capacity
        }
    }
}

extension RFC_1951.Window {

    static let slack = 1 << 10

    func deallocate() {
        unsafe base.deallocate()
    }

    private var raw: UnsafeMutableRawPointer {
        unsafe UnsafeMutableRawPointer(base)
    }

    @inline(__always)
    mutating func reserve(_ additional: Int) {
        if additional > capacity &- count {
            grow(to: count + additional)
        }
    }

    private mutating func grow(to minimum: Int) {
        let newCapacity = Swift.max(minimum, capacity * 2)
        let newBase = UnsafeMutablePointer<Byte>.allocate(capacity: newCapacity)
        unsafe newBase.moveInitialize(from: base, count: count)
        unsafe base.deallocate()
        unsafe base = newBase
        capacity = newCapacity
    }

    @inline(__always)
    mutating func append(_ byte: UInt8) {
        unsafe raw.storeBytes(of: byte, toByteOffset: count, as: UInt8.self)
        count &+= 1
    }

    mutating func append(_ bytes: UnsafeRawBufferPointer) {
        reserve(bytes.count)
        if let source = bytes.baseAddress {
            unsafe (raw + count).copyMemory(from: source, byteCount: bytes.count)
        }
        count &+= bytes.count
    }

    @inline(__always)
    mutating func copy(distance: Int, length: Int) {
        let destination = unsafe raw + count
        let source = unsafe destination - distance
        if distance >= 8 {
            var offset = 0
            repeat {
                let word = unsafe (source + offset).loadUnaligned(as: UInt64.self)
                unsafe (destination + offset).storeBytes(of: word, as: UInt64.self)
                offset &+= 8
            } while offset < length
        } else if distance == 1 {
            let word = UInt64(unsafe source.load(as: UInt8.self)) &* 0x0101_0101_0101_0101
            var offset = 0
            repeat {
                unsafe (destination + offset).storeBytes(of: word, as: UInt64.self)
                offset &+= 8
            } while offset < length
        } else {
            var offset = 0
            repeat {
                let byte = unsafe (source + offset).load(as: UInt8.self)
                unsafe (destination + offset).storeBytes(of: byte, as: UInt8.self)
                offset &+= 1
            } while offset < length
        }
        count &+= length
    }

    func append<Output: RangeReplaceableCollection>(
        to output: inout Output
    ) where Output.Element == Byte {
        unsafe output.append(contentsOf: UnsafeBufferPointer(start: base, count: count))
    }
}
