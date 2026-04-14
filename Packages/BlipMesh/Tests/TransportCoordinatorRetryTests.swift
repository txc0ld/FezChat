import Testing
import Foundation
@preconcurrency import CoreBluetooth
@testable import BlipMesh
import BlipProtocol

private func makeRetryTestPeerID(_ byte: UInt8) -> PeerID {
    PeerID(bytes: Data(repeating: byte, count: PeerID.length))!
}

private func makeRunningCoordinator() -> (coordinator: TransportCoordinator, ble: BLEService, delegate: MockTransportDelegate) {
    let central = MockBLECentralManager()
    central.cmState = .poweredOn

    let peripheral = MockBLEPeripheralManager()
    peripheral.pmState = .poweredOn

    let delegate = MockTransportDelegate()
    let localPeerID = makeRetryTestPeerID(0xAA)
    let ble = BLEService(
        localPeerID: localPeerID,
        centralManager: central,
        peripheralManager: peripheral
    )
    let webSocket = WebSocketTransport(
        localPeerID: localPeerID,
        pinnedCertHashes: [],
        pinnedDomains: [],
        tokenProvider: { "test-token" },
        relayURL: URL(string: "ws://localhost")!
    )
    let coordinator = TransportCoordinator(bleTransport: ble, webSocketTransport: webSocket)
    coordinator.delegate = delegate

    ble.start()
    ble.handleCentralStateChange(.poweredOn)
    ble.handlePeripheralManagerStateChange(.poweredOn)

    return (coordinator, ble, delegate)
}

@Suite("TransportCoordinator onSendFailed callback")
struct TransportCoordinatorRetryTests {
    @Test("onSendFailed fires when both transports fail to deliver")
    func onSendFailedCallbackFires() throws {
        let (coordinator, _, _) = makeRunningCoordinator()
        let targetPeer = makeRetryTestPeerID(0x11)
        let payload = Data("no-transport".utf8)

        var failedCalls: [(Data, PeerID?)] = []
        coordinator.onSendFailed = { data, peer in
            failedCalls.append((data, peer))
        }

        // BLE is running but peer isn't connected → BLE throws.
        // WebSocket not running → onSendFailed fires.
        coordinator.send(data: payload, to: targetPeer)

        #expect(failedCalls.count == 1)
        #expect(failedCalls[0].0 == payload)
        #expect(failedCalls[0].1 == targetPeer)
    }

    @Test("onSendFailed not called when no callback is set")
    func noCallbackSetDoesNotCrash() throws {
        let (coordinator, _, _) = makeRunningCoordinator()
        let targetPeer = makeRetryTestPeerID(0x22)
        let payload = Data("silent-fail".utf8)

        // No onSendFailed set — should not crash
        coordinator.onSendFailed = nil
        coordinator.send(data: payload, to: targetPeer)
    }

    @Test("Multiple send failures each invoke onSendFailed")
    func multipleFailuresCallbackMultipleTimes() throws {
        let (coordinator, _, _) = makeRunningCoordinator()
        let peer1 = makeRetryTestPeerID(0x11)
        let peer2 = makeRetryTestPeerID(0x22)

        var failedCalls: [(Data, PeerID?)] = []
        coordinator.onSendFailed = { data, peer in
            failedCalls.append((data, peer))
        }

        coordinator.send(data: Data("msg1".utf8), to: peer1)
        coordinator.send(data: Data("msg2".utf8), to: peer2)

        #expect(failedCalls.count == 2)
        #expect(failedCalls[0].1 == peer1)
        #expect(failedCalls[1].1 == peer2)
    }
}
