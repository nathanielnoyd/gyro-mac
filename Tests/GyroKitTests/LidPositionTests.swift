import Testing

@testable import GyroKit

struct LidPositionTests {
    @Test(arguments: [
        (0.0, LidPosition.closed), (0.9, .closed),
        (1, .barelyOpen), (59, .barelyOpen),
        (60, .open), (110, .open), (134.9, .open),
        (135, .wideOpen), (180, .wideOpen),
    ])
    func positionForAngle(angle: Double, position: LidPosition) {
        #expect(LidPosition(angle: angle) == position)
    }

    @Test func descriptionsAreSentenceCase() {
        #expect(LidPosition.allCases.map(\.description) == ["Closed", "Barely open", "Open", "Wide open"])
    }
}
