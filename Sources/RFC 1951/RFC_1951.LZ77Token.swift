internal import Byte_Primitives

extension RFC_1951 {

    enum LZ77Token {

        case literal(Byte)

        case reference(length: Int, distance: Int)
    }
}
