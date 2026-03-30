import Foundation
import BlipProtocol
import BlipMesh
import os.log

/// Gossip relay middleware that sits between TransportCoordinator and MessageService.
///
/// Intercepts incoming packets, runs them through the GossipRouter for deduplication
/// and adaptive relay decisions, then forwards new packets to MessageService for local
/// processing. Relayed packets are re-broadcast to all connected peers except the source.
///
/// Architecture:
/// ```
/// BLEService → TransportCoordinator → MeshRelayService → MessageService
///                      ↑                     │
///                      └─── relay broadcast ──┘
/// ```
///
/// Spec references: Section 5.5 (gossip routing), 8.3 (adaptive relay), 8.9 (SOS priority).
final class MeshRelayService: @unchecked Sendable {

    // MARK: - Dependencies

    /// The gossip routing engine (dedup, TTL, relay probability).
    let gossipRouter: GossipRouter

    /// The adaptive relay probability calculator.
    let adaptiveRelay: AdaptiveRelay

    /// Reference to the transport layer for relaying packets.
    weak var transport: TransportCoordinator?

    /// Downstream delegate (MessageService) for local packet delivery.
    weak var delegate: (any TransportDelegate)?

    // MARK: - Internals

    private let logger = Logger(subsystem: "com.blip", category: "MeshRelay")
    private let relayQueue = DispatchQueue(label: "com.blip.relay", qos: .userInitiated)

    // MARK: - Init

    init(
        gossipRouter: GossipRouter = GossipRouter(),
        adaptiveRelay: AdaptiveRelay? = nil,
        transport: TransportCoordinator? = nil
    ) {
        self.gossipRouter = gossipRouter
        self.adaptiveRelay = adaptiveRelay ?? gossipRouter.adaptiveRelay
        self.transport = transport
        self.gossipRouter.delegate = self
    }

    // MARK: - Diagnostics

    /// Current relay metrics for the debug overlay.
    var metrics: (received: UInt64, relayed: UInt64, dropped: UInt64) {
        (gossipRouter.packetsReceived, gossipRouter.packetsRelayed, gossipRouter.packetsDropped)
    }
}

// MARK: - TransportDelegate

extension MeshRelayService: TransportDelegate {

    func transport(_ transport: any Transport, didReceiveData data: Data, from peerID: PeerID) {
        // Decode the raw data into a Packet for the gossip router.
        let packet: Packet
        do {
            packet = try PacketSerializer.decode(data)
        } catch {
            // Can't decode — still forward raw data to MessageService for its own handling.
            logger.warning("Relay decode failed, forwarding raw: \(error.localizedDescription)")
            delegate?.transport(transport, didReceiveData: data, from: peerID)
            return
        }

        // Run through gossip pipeline: dedup → TTL → relay decision.
        // Returns true if this is a NEW packet we should process locally.
        let isNew = gossipRouter.handleIncoming(packet: packet, from: peerID)

        if isNew {
            // Forward original data to MessageService for local processing.
            delegate?.transport(transport, didReceiveData: data, from: peerID)
        }

        // Update queue fill ratio for congestion-aware relay decisions.
        if let coordinator = self.transport {
            let fill = Double(coordinator.localQueueCount) / Double(TransportCoordinator.maxLocalQueueSize)
            adaptiveRelay.queueFillRatio = fill
        }
    }

    func transport(_ transport: any Transport, didConnect peerID: PeerID) {
        // Update the adaptive relay's peer count.
        if let coordinator = self.transport {
            adaptiveRelay.connectedPeerCount = coordinator.connectedPeers.count
        }

        // Update directed routing table — this peer is directly reachable.
        gossipRouter.directedRouter.updateRoute(peerID: peerID, viaPeer: peerID, hopCount: 1)

        // Deliver any store-and-forward cached packets for this peer.
        let cached = gossipRouter.deliverCachedPackets(to: peerID)
        if !cached.isEmpty {
            logger.info("Delivering \(cached.count) cached packet(s) to \(peerID)")
            for cachedPacket in cached {
                do {
                    let wireData = try PacketSerializer.encode(cachedPacket)
                    self.transport?.send(data: wireData, to: peerID)
                } catch {
                    logger.error("Failed to encode cached packet: \(error.localizedDescription)")
                }
            }
        }

        // Forward connect event downstream to MessageService.
        delegate?.transport(transport, didConnect: peerID)
    }

    func transport(_ transport: any Transport, didDisconnect peerID: PeerID) {
        // Update peer count.
        if let coordinator = self.transport {
            adaptiveRelay.connectedPeerCount = max(0, coordinator.connectedPeers.count - 1)
        }

        // Remove routes via the disconnected peer.
        gossipRouter.directedRouter.removeRoutes(viaPeer: peerID)

        // Forward downstream.
        delegate?.transport(transport, didDisconnect: peerID)
    }

    func transport(_ transport: any Transport, didChangeState state: TransportState) {
        // Forward downstream.
        delegate?.transport(transport, didChangeState: state)
    }
}

// MARK: - GossipRouterDelegate

extension MeshRelayService: GossipRouterDelegate {

    func gossipRouter(_ router: GossipRouter, shouldRelay packet: Packet, excluding excludedPeer: PeerID) {
        guard let transport = self.transport else {
            logger.warning("Cannot relay — transport not available")
            return
        }

        // Encode the packet (with decremented TTL) for relay.
        let wireData: Data
        do {
            wireData = try PacketSerializer.encode(packet)
        } catch {
            logger.error("Failed to encode relay packet: \(error.localizedDescription)")
            return
        }

        // Check if this is a directed DM — try unicast first via routing table.
        if let recipientID = packet.recipientID,
           let nextHop = gossipRouter.directedRouter.findRoute(to: recipientID) {
            // Directed relay: send only to the next hop toward the destination.
            do {
                try transport.bleTransport.send(data: wireData, to: nextHop)
                print("[Blip-Relay] Directed relay to \(nextHop) for recipient \(recipientID)")
                return
            } catch {
                // Directed send failed — fall through to gossip broadcast.
                logger.debug("Directed relay failed, falling back to gossip: \(error.localizedDescription)")
            }
        }

        // Gossip relay: broadcast to all connected peers except the source.
        transport.broadcastExcluding(data: wireData, excludedPeer: excludedPeer)

        let isSOS = packet.type.isSOS
        print("[Blip-Relay] \(isSOS ? "SOS " : "")Gossip relay to \(transport.connectedPeers.count - 1) peer(s), TTL=\(packet.ttl)")
    }
}
