internal import Byte

extension IETF.RFC.`1951` {

    enum LZ77Token {

        case literal(Byte)

        case reference(length: Int, distance: Int)
    }
}
