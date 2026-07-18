import Foundation

/// Pure decision for the "restart Shorkut" flow: the current instance must only
/// terminate itself once the replacement instance has actually launched.
/// Terminating unconditionally (as the old code did) meant a failed relaunch
/// left the user with no running app at all.
public enum AppRestart {
    public enum Outcome: Equatable {
        /// Replacement launched — safe to terminate the current instance.
        case relaunchedTerminateSelf
        /// Launch failed — keep the current instance alive and surface an error.
        case failedKeepRunning
    }

    public static func outcome(launchedAppExists: Bool, error: Error?) -> Outcome {
        (error == nil && launchedAppExists) ? .relaunchedTerminateSelf : .failedKeepRunning
    }
}
