import Foundation
import BackgroundTasks

enum BackgroundRefresh {
    static let identifier = "dev.shed.schedule.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                let result = await AppServices.shared.repository.refresh()
                schedule()
                refreshTask.setTaskCompleted(success: result.successful)
            }
            refreshTask.expirationHandler = {
                work.cancel()
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
