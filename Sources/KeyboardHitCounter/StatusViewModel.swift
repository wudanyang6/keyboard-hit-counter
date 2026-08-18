import Foundation
import Combine
import KeyboardHitCounterCore

public enum PermissionState {
    case unknown
    case denied
    case granted
}

public final class StatusViewModel: ObservableObject {
    @Published public var rows: [AppRow] = []
    @Published public var permissionState: PermissionState = .unknown

    public init() {}
}