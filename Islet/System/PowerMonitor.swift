import Foundation
import IOKit.ps

struct PowerStatus: Equatable {
    var level: Int
    var isPluggedIn: Bool
}

final class PowerMonitor {
    var onChange: ((PowerStatus) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lastStatus: PowerStatus?

    func start() {
        lastStatus = readStatus()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().report()
        }, context).takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func report() {
        guard let status = readStatus() else { return }
        let hasPlugChanged = status.isPluggedIn != lastStatus?.isPluggedIn
        lastStatus = status
        if hasPlugChanged {
            onChange?(status)
        }
    }

    private func readStatus() -> PowerStatus? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [AnyObject]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let level = description[kIOPSCurrentCapacityKey] as? Int,
                  let state = description[kIOPSPowerSourceStateKey] as? String else { continue }
            return PowerStatus(level: level, isPluggedIn: state == kIOPSACPowerValue)
        }
        return nil
    }
}
