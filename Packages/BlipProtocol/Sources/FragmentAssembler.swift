import Foundation
import os.log

/// Errors from fragment assembly.
public enum FragmentAssemblyError: Error, Sendable, Equatable {
    case tooManyConcurrentAssemblies
    case duplicateFragment(fragmentID: Data, index: UInt16)
    case assemblyTimedOut(fragmentID: Data)
    case inconsistentTotal(fragmentID: Data, expected: UInt16, got: UInt16)
}

/// Result of feeding a fragment into the assembler.
public enum FragmentAssemblyResult: Sendable, Equatable {
    /// Fragment accepted, assembly still in progress.
    case incomplete(received: Int, total: Int)
    /// All fragments received; here is the reassembled payload.
    case complete(Data)
}

/// Identifies a fragment group originating from a specific peer.
///
/// Per-peer keying prevents cross-peer fragment contamination: two peers that
/// happen to generate the same random 4-byte `fragmentID` within the same
/// 30-second assembly window must not have their fragments stitched together.
public struct FragmentAssemblyKey: Hashable, Sendable {
    public let senderID: PeerID
    public let fragmentID: Data

    public init(senderID: PeerID, fragmentID: Data) {
        self.senderID = senderID
        self.fragmentID = fragmentID
    }
}

/// Reassembles fragments into complete payloads.
///
/// Per spec Section 5.7:
/// - Max 128 concurrent fragment assemblies across all peers
/// - Fragment lifetime: 30 seconds
/// - LRU eviction when the limit is exceeded
///
/// **Per-peer isolation:** assemblies are keyed by `(senderID, fragmentID)` rather
/// than `fragmentID` alone. Fragment IDs are 4 random bytes; with N peers sending
/// many concurrent messages, birthday-paradox collisions between peers are likely.
/// Without per-peer keying, peer A's fragment 0 could be stitched together with
/// peer B's fragment 1, producing garbage payloads and decryption failures.
public final class FragmentAssembler: Sendable {

    /// Maximum concurrent assemblies.
    public static let maxConcurrentAssemblies = 128

    /// Fragment lifetime in seconds.
    public static let fragmentLifetime: TimeInterval = 30.0

    private static let logger = Logger(subsystem: "com.blip", category: "FragmentAssembler")

    /// Internal assembly state for one fragment group.
    private final class Assembly: @unchecked Sendable {
        let key: FragmentAssemblyKey
        let total: UInt16
        var fragments: [UInt16: Data]
        let createdAt: Date
        var lastAccessedAt: Date

        init(key: FragmentAssemblyKey, total: UInt16) {
            self.key = key
            self.total = total
            self.fragments = [:]
            self.createdAt = Date()
            self.lastAccessedAt = Date()
        }

        var isComplete: Bool {
            guard fragments.count == Int(total) else { return false }
            return (0 ..< total).allSatisfy { fragments[$0] != nil }
        }

        var isExpired: Bool {
            Date().timeIntervalSince(createdAt) > FragmentAssembler.fragmentLifetime
        }

        /// Reassemble all fragments in index order.
        func reassemble() -> Data {
            var result = Data()
            for i in 0 ..< total {
                guard let chunk = fragments[i] else {
                    preconditionFailure(
                        "FragmentAssembler: missing fragment at index \(i) " +
                            "(total=\(total), present keys=\(fragments.keys.sorted())). " +
                            "isComplete returned true but the index set is incomplete."
                    )
                }
                result.append(chunk)
            }
            return result
        }
    }

    /// Lock for thread-safe access to assemblies.
    private let lock = NSLock()

    /// Active assemblies keyed by (senderID, fragmentID).
    // Protected by `lock`; mutable access is always serialized.
    private nonisolated(unsafe) var assemblies: [FragmentAssemblyKey: Assembly] = [:]

    /// Ordered list of keys for LRU eviction.
    // Protected by `lock`; mutable access is always serialized.
    private nonisolated(unsafe) var lruOrder: [FragmentAssemblyKey] = []

    /// Backing storage for `onEviction`. Protected by `lock`.
    private nonisolated(unsafe) var _onEviction: (@Sendable (FragmentAssemblyKey, _ received: Int, _ total: Int) -> Void)?

    /// Notified when an incomplete assembly is evicted by the LRU policy. Useful
    /// for surfacing "reassembly dropped" diagnostics to the debug overlay.
    public var onEviction: (@Sendable (FragmentAssemblyKey, _ received: Int, _ total: Int) -> Void)? {
        get { lock.withLock { _onEviction } }
        set { lock.withLock { _onEviction = newValue } }
    }

    public init() {}

    // MARK: - Public API

    /// Feed a fragment into the assembler.
    ///
    /// - Parameters:
    ///   - fragment: The fragment to add.
    ///   - senderID: The peer that sent this fragment. Used to scope assembly
    ///     state so two peers cannot collide on the same `fragmentID`.
    /// - Returns: `.incomplete` if more fragments are needed, `.complete` with the
    ///   reassembled payload when all fragments have arrived.
    /// - Throws: `FragmentAssemblyError` on duplicate fragments, assembly limit exceeded
    ///   (after eviction), or inconsistent total counts.
    public func receive(_ fragment: Fragment, from senderID: PeerID) throws -> FragmentAssemblyResult {
        lock.lock()
        defer { lock.unlock() }

        // Purge expired assemblies first.
        purgeExpired()

        let key = FragmentAssemblyKey(senderID: senderID, fragmentID: fragment.fragmentID)

        if let existing = assemblies[key] {
            // Validate consistent total
            guard existing.total == fragment.total else {
                throw FragmentAssemblyError.inconsistentTotal(
                    fragmentID: fragment.fragmentID,
                    expected: existing.total,
                    got: fragment.total
                )
            }

            // Check for duplicate
            guard existing.fragments[fragment.index] == nil else {
                throw FragmentAssemblyError.duplicateFragment(
                    fragmentID: fragment.fragmentID,
                    index: fragment.index
                )
            }

            guard fragment.index < existing.total else {
                Self.logger.error(
                    "Dropping fragment with out-of-range index \(fragment.index, privacy: .public) (total=\(existing.total, privacy: .public))"
                )
                return .incomplete(received: existing.fragments.count, total: Int(existing.total))
            }

            // Add fragment
            existing.fragments[fragment.index] = fragment.data
            existing.lastAccessedAt = Date()
            touchLRU(key)

            if existing.isComplete {
                let payload = existing.reassemble()
                removeAssembly(key)
                return .complete(payload)
            }

            return .incomplete(
                received: existing.fragments.count,
                total: Int(existing.total)
            )
        } else {
            // New assembly — evict LRU if we're at capacity.
            if assemblies.count >= FragmentAssembler.maxConcurrentAssemblies {
                evictLRU()
            }

            guard fragment.index < fragment.total else {
                Self.logger.error(
                    "Dropping fragment with out-of-range index \(fragment.index, privacy: .public) (total=\(fragment.total, privacy: .public))"
                )
                return .incomplete(received: 0, total: Int(fragment.total))
            }

            let assembly = Assembly(key: key, total: fragment.total)
            assembly.fragments[fragment.index] = fragment.data
            assemblies[key] = assembly
            lruOrder.append(key)

            if assembly.isComplete {
                let payload = assembly.reassemble()
                removeAssembly(key)
                return .complete(payload)
            }

            return .incomplete(
                received: assembly.fragments.count,
                total: Int(assembly.total)
            )
        }
    }

    /// Cancel and remove a specific assembly.
    public func cancel(fragmentID: Data, from senderID: PeerID) {
        lock.lock()
        defer { lock.unlock() }
        removeAssembly(FragmentAssemblyKey(senderID: senderID, fragmentID: fragmentID))
    }

    /// Remove all assemblies.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        assemblies.removeAll()
        lruOrder.removeAll()
    }

    /// Number of active assemblies.
    public var activeAssemblyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return assemblies.count
    }

    /// Purge expired assemblies and return the evicted keys.
    @discardableResult
    public func purgeExpiredAssemblies() -> [FragmentAssemblyKey] {
        lock.lock()
        defer { lock.unlock() }
        return purgeExpired()
    }

    // MARK: - Internal

    @discardableResult
    private func purgeExpired() -> [FragmentAssemblyKey] {
        var purged: [FragmentAssemblyKey] = []
        for (id, assembly) in assemblies {
            if assembly.isExpired {
                purged.append(id)
            }
        }
        for id in purged {
            removeAssembly(id)
        }
        return purged
    }

    private func evictLRU() {
        guard let oldest = lruOrder.first else { return }
        // Surface the eviction so the app layer can log/warn about dropped
        // reassembly attempts (instead of silently losing a partial message).
        //
        // We're already holding `lock` here (this is called from `receive`).
        // Read `_onEviction` directly and dispatch the callback off-queue so
        // user code doesn't run under our lock.
        if let assembly = assemblies[oldest] {
            let handler = _onEviction
            let received = assembly.fragments.count
            let total = Int(assembly.total)
            let key = oldest
            if let handler {
                DispatchQueue.global(qos: .utility).async {
                    handler(key, received, total)
                }
            }
        }
        removeAssembly(oldest)
    }

    private func removeAssembly(_ key: FragmentAssemblyKey) {
        assemblies.removeValue(forKey: key)
        lruOrder.removeAll { $0 == key }
    }

    private func touchLRU(_ key: FragmentAssemblyKey) {
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }
}
