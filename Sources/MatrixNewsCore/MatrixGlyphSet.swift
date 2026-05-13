import Foundation

public enum MatrixGlyphSet {
    public static let koreanMatrix = "가나다라마바사아자차카타파하뉴스속보정치경제사회세계국제문화과학기술스포츠현장단독분석오늘내일한국서울정부국회시장산업외교기후법원검찰"
}

public enum MatrixGlyphOrientation: CaseIterable, Sendable {
    case normal
    case mirrored
    case upsideDown
    case mirroredUpsideDown

    public static func orientation(column: Int, row: Int) -> MatrixGlyphOrientation {
        let hash = positiveHash(column: column, row: row)
        if hash % 997 == 0 {
            return .upsideDown
        }
        if hash % 29 == 0 {
            return .mirrored
        }
        return .normal
    }

    private static func positiveHash(column: Int, row: Int) -> Int {
        var value = column &* 73_856_093
        value ^= row &* 19_349_663
        value ^= value >> 13
        return abs(value)
    }

    public var xScale: Double {
        switch self {
        case .normal, .upsideDown:
            return 1
        case .mirrored, .mirroredUpsideDown:
            return -1
        }
    }

    public var yScale: Double {
        switch self {
        case .normal, .mirrored:
            return 1
        case .upsideDown, .mirroredUpsideDown:
            return -1
        }
    }
}

public enum MatrixRainDepthLayer: CaseIterable, Sendable {
    case distant
    case middle
    case near

    public var columnWidth: Double {
        switch self {
        case .distant: return 31
        case .middle: return 24
        case .near: return 18
        }
    }

    public var rowHeight: Double {
        switch self {
        case .distant: return 29
        case .middle: return 25
        case .near: return 22
        }
    }

    public var fontSize: Double {
        switch self {
        case .distant: return 12
        case .middle: return 15
        case .near: return 19
        }
    }

    public var speed: Double {
        switch self {
        case .distant: return 0.58
        case .middle: return 0.92
        case .near: return 1.34
        }
    }

    public var tailLength: Int {
        switch self {
        case .distant: return 13
        case .middle: return 18
        case .near: return 24
        }
    }

    public var glowRadius: Double {
        switch self {
        case .distant: return 1.8
        case .middle: return 3.2
        case .near: return 5.2
        }
    }

    public var baseOpacity: Double {
        switch self {
        case .distant: return 0.20
        case .middle: return 0.34
        case .near: return 0.50
        }
    }
}

public struct MatrixRainCinematicProfile: Sendable {
    public var layer: MatrixRainDepthLayer

    public init(layer: MatrixRainDepthLayer) {
        self.layer = layer
    }

    public func opacity(distanceFromHead distance: Int) -> Double {
        if distance == 0 {
            switch layer {
            case .distant: return 0.52
            case .middle: return 0.78
            case .near: return 0.88
            }
        }
        if distance < 0 || distance > layer.tailLength {
            return 0.025
        }

        let progress = Double(distance) / Double(layer.tailLength)
        let trail = pow(1 - progress, 2.35)
        return max(0.03, layer.baseOpacity * trail)
    }
}
