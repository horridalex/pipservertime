import Foundation
import Network

/// 셀룰러(데이터) 사용 여부 감지 → 측정 오차가 커질 수 있다는 경고에 사용
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isCellular = false
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isCellular = cellular
                self?.isConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.monitor"))
    }

    deinit { monitor.cancel() }
}
