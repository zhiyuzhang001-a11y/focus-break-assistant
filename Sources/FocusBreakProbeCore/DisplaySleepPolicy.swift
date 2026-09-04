public enum DisplaySleepPolicy {
    /// Aggregates per-display sleep values for the displays that are currently
    /// online. An empty or failed query is unknown rather than an invented
    /// awake state.
    public static func aggregate(onlineDisplaySleepStates: [Bool]?) -> TriState {
        guard let onlineDisplaySleepStates, !onlineDisplaySleepStates.isEmpty else {
            return .unknown
        }
        return onlineDisplaySleepStates.allSatisfy { $0 } ? .yes : .no
    }
}
