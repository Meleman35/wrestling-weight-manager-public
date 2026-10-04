import Foundation

// Presentation model only: replay the scorer's saved ledger; never award points here.
@MainActor
struct WrestlingVideoScoreFrame: Equatable {
    let redName: String
    let otherName: String
    let red: Int
    let other: Int
    let otherIsGreen: Bool
    let caption: String

    init(state: [String: Any]) {
        redName = String(((state["red_name"] as? String) ?? "Red").prefix(80))
        otherName = String(((state["other_name"] as? String) ?? "Opponent").prefix(80))
        otherIsGreen = state["style"] as? String == "folkstyle"
        var totals = ["red": 0.0, "other": 0.0]
        for entry in (state["ledger"] as? [[String: Any]]) ?? [] where entry["voided"] as? Bool != true {
            guard let corner = entry["corner"] as? String, totals[corner] != nil,
                  let value = entry["points"] as? NSNumber, value.doubleValue.isFinite else { continue }
            totals[corner, default: 0] += min(100000, max(-100000, value.doubleValue))
        }
        red = Int(min(100000, max(-100000, totals["red"] ?? 0)))
        other = Int(min(100000, max(-100000, totals["other"] ?? 0)))
        caption = state["status"] as? String == "complete" ? "FINAL" : String(((state["phaseLabel"] as? String) ?? "MATCH").prefix(48))
    }
}

@MainActor
enum WrestlingVideoScoreTimeline {
    struct Entry { let seconds: Double; let frame: WrestlingVideoScoreFrame }
    static func entries(_ row: [String: Any], duration: Double) -> [Entry] {
        guard duration.isFinite, duration > 0 else { return [] }
        // Stable sequence ordering also preserves an Undo or correction at the same timestamp.
        let events = ((row["events"] as? [[String: Any]]) ?? []).enumerated().compactMap { index, event -> (Int, Double, [String: Any])? in
            guard let at = event["atMs"] as? NSNumber, at.doubleValue.isFinite, at.doubleValue >= 0,
                  let state = event["state"] as? [String: Any] else { return nil }
            let seconds = at.doubleValue / 1000
            // An event exactly at the end has no corresponding video frame.
            guard seconds < duration else { return nil }
            return (index, seconds, state)
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var out: [Entry] = []
        for (_, seconds, state) in events {
            let value = WrestlingVideoScoreFrame(state: state)
            if out.last?.seconds == seconds { out.removeLast() }
            if out.last?.frame != value { out.append(Entry(seconds: seconds, frame: value)) }
        }
        return out
    }
    static func frame(_ entries: [Entry], at seconds: Double) -> WrestlingVideoScoreFrame? {
        guard seconds.isFinite else { return nil }
        return entries.last(where: { $0.seconds <= max(0, seconds) })?.frame
    }
}
