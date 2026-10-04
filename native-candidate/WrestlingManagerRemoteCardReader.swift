import Foundation

/// One fresh card placement per attempt. This wraps the existing Bluetooth
/// reader; credential-to-roster authorization remains the host's responsibility.
@MainActor final class WrestlingManagerRemoteCardReader {
    enum Failure: Error { case timedOut, unavailable(String) }
    private let isAvailable: () -> Bool
    private let isCardPresent: () -> Bool
    private let startRead: (@escaping (Result<String, Error>) -> Void) -> Void
    private let cancelRead: () -> Void
    private var operation: UUID?
    private var waiting: Task<Void, Never>?
    init(isAvailable: @escaping () -> Bool, isCardPresent: @escaping () -> Bool,
         startRead: @escaping (@escaping (Result<String, Error>) -> Void) -> Void,
         cancelRead: @escaping () -> Void) {
        self.isAvailable = isAvailable; self.isCardPresent = isCardPresent
        self.startRead = startRead; self.cancelRead = cancelRead
    }
    func read(_ completion: @escaping (Result<String, Error>) -> Void) {
        cancel(); let ticket = UUID(); operation = ticket
        waiting = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.operation == ticket, !Task.isCancelled {
                guard self.isAvailable() else {
                    self.operation = nil; self.waiting = nil
                    completion(.failure(Failure.unavailable("Reconnect NFC reader."))); return
                }
                if !self.isCardPresent() {
                    self.startRead { [weak self] result in
                        guard let self, self.operation == ticket else { return }
                        self.operation = nil; self.waiting = nil; completion(result)
                    }
                    return
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
        }
    }
    func cancel() {
        operation = nil; waiting?.cancel(); waiting = nil; cancelRead()
    }
}
