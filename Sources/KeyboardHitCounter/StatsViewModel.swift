import Foundation
import Combine
import KeyboardHitCounterCore

public final class StatsViewModel: ObservableObject {
    @Published public var snapshot: StatsSnapshot = .empty

    public init() {}
}