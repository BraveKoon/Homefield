import Foundation

/// 빌드 종류.
///
/// 데모 빌드는 TestFlight 워크플로를 `demo_build` 를 켜고 실행하면 만들어진다 (컴파일 조건 DEMO_BUILD).
/// 심사·소개용으로, 실제 구단·선수 없이 앱을 보여 준다.
/// - 가상 팀과 가상 선수만 쓴다 (실제 경기·선수 기록을 받지 않는다)
/// - 팀 로고와 선수 사진을 받지 않는다
/// - 카드 포인트를 3,000 으로 고정한다
/// - 로그인과 계정 동기화를 끈다 (실제 계정 데이터를 건드리지 않는다)
/// - 저장 파일과 설정을 일반 빌드와 따로 쓴다
enum BuildFlavor {
    static let isDemo: Bool = {
        #if DEMO_BUILD
        return true
        #else
        return false
        #endif
    }()

    /// 데모 빌드의 카드 포인트
    static let demoPoints = 3_000

    /// 데모 빌드는 일반 빌드의 저장 파일을 덮어쓰지 않도록 이름을 따로 쓴다
    static func storeName(_ name: String) -> String {
        isDemo ? "demo-\(name)" : name
    }

    /// 앱 설정 저장소. 데모 빌드는 일반 빌드와 따로 쓴다.
    static var defaults: UserDefaults {
        guard isDemo else { return .standard }
        return UserDefaults(suiteName: "com.bravekoon.homefield.demo") ?? .standard
    }
}
