import Foundation

/// レガシーの固定長レコードと同じバイト配置を持つレコード定義。
/// 文字データは Shift_JIS (ASCII 互換・全角 2 バイト=2 セル) で格納する。
public enum FieldType: Sendable {
    /// PIC X(n)
    case x(Int)
    /// PIC 9(n)[V9(m)] DISPLAY (符号付きは末尾桁オーバーパンチ)
    case n9(digits: Int, scale: Int, signed: Bool)
    /// COMP-3
    case comp3(digits: Int, scale: Int, signed: Bool)
    /// COMP / BINARY (ビッグエンディアン、桁数からサイズ決定 1-2-4-8)
    case comp(digits: Int, scale: Int, signed: Bool)
    /// binary-char / binary-short / binary-long 等 (ネイティブ=リトルエンディアン)
    case native(bytes: Int, signed: Bool)
    /// 未使用領域
    case filler(Int)

    public var size: Int {
        switch self {
        case .x(let n), .filler(let n): return n
        case .n9(let d, _, _): return d
        case .comp3(let d, _, _): return d / 2 + 1
        case .comp(let d, _, _): return d <= 2 ? 1 : (d <= 4 ? 2 : (d <= 9 ? 4 : 8))
        case .native(let b, _): return b
        }
    }
    public var scale: Int {
        switch self {
        case .n9(_, let s, _), .comp3(_, let s, _), .comp(_, let s, _): return s
        default: return 0
        }
    }
}

public struct FieldDef: Sendable {
    public let name: String
    public let type: FieldType
    public let offset: Int
}

public final class Layout: @unchecked Sendable {
    public let name: String
    public private(set) var fields: [String: FieldDef] = [:]
    public private(set) var order: [FieldDef] = []
    public private(set) var size = 0

    public init(_ name: String, _ defs: [(String, FieldType)]) {
        self.name = name
        var off = 0
        for (n, t) in defs {
            let d = FieldDef(name: n, type: t, offset: off)
            if !n.isEmpty { fields[n] = d }
            order.append(d)
            off += t.size
        }
        size = off
    }

    /// REDEFINES 用: 既存オフセットへ別名項目を追加
    public func redefine(_ name: String, _ type: FieldType, at offset: Int) {
        let d = FieldDef(name: name, type: type, offset: offset)
        fields[name] = d
    }

    public func offset(_ name: String) -> Int { fields[name]!.offset }
}

public enum SJIS {
    public static func encode(_ s: String, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        for ch in s {
            var b: [UInt8]
            if ch.isASCII, let a = ch.asciiValue { b = [a] }
            else if let d = String(ch).data(using: .shiftJIS) { b = [UInt8](d) }
            else { b = [0x3f] }
            if out.count + b.count > size { break }
            out.append(contentsOf: b)
            b.removeAll()
        }
        while out.count < size { out.append(0x20) }
        return out
    }

    public static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) { return String(decoding: bytes, as: UTF8.self) }
        if bytes.allSatisfy({ $0 < 0x80 }) {
            return String(bytes.map { $0 < 0x20 ? Character(" ") : Character(UnicodeScalar($0)) })
        }
        if let s = String(data: Data(bytes), encoding: .shiftJIS) { return s }
        return String(bytes.map { ($0 >= 0x20 && $0 < 0x7f) ? Character(UnicodeScalar($0)) : Character("?") })
    }
}

public struct Record: Sendable {
    public let layout: Layout
    public var bytes: [UInt8]

    /// INITIALIZE 相当: 英数字は空白、数値は 0
    public init(_ layout: Layout) {
        self.layout = layout
        bytes = [UInt8](repeating: 0x20, count: layout.size)
        for f in layout.order {
            switch f.type {
            case .x: break
            case .filler: break
            default: setInt(f, 0)
            }
        }
    }

    public init(_ layout: Layout, bytes: [UInt8]) {
        self.layout = layout
        var b = bytes
        if b.count < layout.size { b += [UInt8](repeating: 0x20, count: layout.size - b.count) }
        self.bytes = Array(b.prefix(layout.size))
    }

    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    private func def(_ name: String) -> FieldDef {
        guard let f = layout.fields[name] else { fatalError("Unknown field \(name) in \(layout.name)") }
        return f
    }

    public func str(_ name: String) -> String {
        let f = def(name)
        return SJIS.decode(bytes[f.offset..<(f.offset + f.type.size)])
    }

    public mutating func set(_ name: String, _ value: String) {
        let f = def(name)
        switch f.type {
        case .x, .filler:
            bytes.replaceSubrange(f.offset..<(f.offset + f.type.size), with: SJIS.encode(value, size: f.type.size))
        default:
            let (v, sc) = Cobol.numval(value)
            setInt(f, Cobol.rescale(v, from: sc, to: f.type.scale))
        }
    }

    public func raw(_ name: String) -> [UInt8] {
        let f = def(name)
        return Array(bytes[f.offset..<(f.offset + f.type.size)])
    }

    public mutating func setRaw(_ name: String, _ data: [UInt8]) {
        let f = def(name)
        var d = Array(data.prefix(f.type.size))
        while d.count < f.type.size { d.append(0x20) }
        bytes.replaceSubrange(f.offset..<(f.offset + f.type.size), with: d)
    }

    /// 数値項目をスケール付き整数で取得
    public func int(_ name: String) -> Int64 {
        let f = def(name)
        let b = bytes[f.offset..<(f.offset + f.type.size)]
        switch f.type {
        case .x, .filler:
            return Cobol.numval(SJIS.decode(b)).0
        case .n9(_, _, let signed):
            var v: Int64 = 0
            var neg = false
            for (i, c) in b.enumerated() {
                var d = c
                if signed, i == b.count - 1, c >= 0x70, c <= 0x79 { neg = true; d = c - 0x40 }
                if d >= 0x30, d <= 0x39 { v = v * 10 + Int64(d - 0x30) } else { v = v * 10 }
            }
            return neg ? -v : v
        case .comp3:
            var v: Int64 = 0
            let arr = Array(b)
            for (i, c) in arr.enumerated() {
                v = v * 10 + Int64(c >> 4)
                if i < arr.count - 1 { v = v * 10 + Int64(c & 0x0f) }
            }
            let sign = arr.last! & 0x0f
            return (sign == 0x0d || sign == 0x0b) ? -v : v
        case .comp(_, _, let signed):
            var u: UInt64 = 0
            for c in b { u = (u << 8) | UInt64(c) }
            return Self.signExtend(u, bytes: b.count, signed: signed)
        case .native(_, let signed):
            var u: UInt64 = 0
            for c in b.reversed() { u = (u << 8) | UInt64(c) }
            return Self.signExtend(u, bytes: b.count, signed: signed)
        }
    }

    private static func signExtend(_ u: UInt64, bytes: Int, signed: Bool) -> Int64 {
        if !signed || bytes == 8 { return Int64(bitPattern: u) }
        let bits = UInt64(bytes * 8)
        if u & (1 << (bits - 1)) != 0 { return Int64(bitPattern: u | ~((1 << bits) - 1)) }
        return Int64(u)
    }

    public mutating func setInt(_ name: String, _ value: Int64) { setInt(def(name), value) }

    mutating func setInt(_ f: FieldDef, _ value: Int64) {
        var out: [UInt8]
        switch f.type {
        case .x(let n), .filler(let n):
            out = SJIS.encode(String(value), size: n)
        case .n9(let digits, _, let signed):
            out = Array(Cobol.z(value, digits).utf8)
            if signed, value < 0 { out[out.count - 1] += 0x40 }
        case .comp3(let digits, _, let signed):
            let size = digits / 2 + 1
            let ds = Array(Cobol.z(value, size * 2 - 1).utf8).map { $0 - 0x30 }
            out = []
            for i in 0..<size {
                let hi = ds[i * 2]
                let lo: UInt8 = i == size - 1 ? (signed ? (value < 0 ? 0x0d : 0x0c) : 0x0f) : ds[i * 2 + 1]
                out.append(hi << 4 | lo)
            }
        case .comp(let digits, _, let signed):
            let size = f.type.size
            let v = Cobol.truncate(value, digits: digits, signed: signed)
            let u = UInt64(bitPattern: v)
            out = (0..<size).map { UInt8((u >> UInt64((size - 1 - $0) * 8)) & 0xff) }
        case .native(let size, _):
            let u = UInt64(bitPattern: value)
            out = (0..<size).map { UInt8((u >> UInt64($0 * 8)) & 0xff) }
        }
        bytes.replaceSubrange(f.offset..<(f.offset + f.type.size), with: out)
    }

    public subscript(_ name: String) -> String {
        get { str(name) }
        set { set(name, newValue) }
    }
}
