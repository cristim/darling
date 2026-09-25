// Minimal, inert Symbols framework surface used by apps linking SwiftUI.
// The types and protocol conformances are real Swift values; animation is
// delegated to the UI renderer and is not implemented here.

public struct SymbolEffectConfiguration: Hashable, Sendable {
    public init() {}
}

public protocol SymbolEffect: Hashable, Sendable {
    var configuration: SymbolEffectConfiguration { get }
}

public protocol ContentTransitionSymbolEffect {}

public struct SymbolEffectOptions: Hashable, Sendable {
    private var value: UInt64 = 0

    public init() {}
    public static var `default`: Self { .init() }
    public static var nonRepeating: Self { .init() }
}

public struct BounceSymbolEffect: SymbolEffect {
    private var value: UInt64 = 0

    public init() {}
    public var down: Self { self }
    public var wholeSymbol: Self { self }
    public var configuration: SymbolEffectConfiguration { .init() }
}

public struct ReplaceSymbolEffect: SymbolEffect, ContentTransitionSymbolEffect {
    private var value: UInt64 = 0

    public init() {}
    public var downUp: Self { self }
    public var configuration: SymbolEffectConfiguration { .init() }
}

public struct AutomaticSymbolEffect: SymbolEffect, ContentTransitionSymbolEffect {
    private var value: UInt64 = 0

    public init() {}
    public var configuration: SymbolEffectConfiguration { .init() }
}

public struct VariableColorSymbolEffect: SymbolEffect {
    private var value: UInt64 = 0

    public init() {}
    public var cumulative: Self { self }
    public var dimInactiveLayers: Self { self }
    public var iterative: Self { self }
    public var configuration: SymbolEffectConfiguration { .init() }
}
