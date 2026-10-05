import CryptoKit
import SwiftUI
import UIKit

/// 네이버 스포츠 이미지 주소 (2026-10-05 확인: 팀 로고 PNG, 선수 사진 PNG, 없는 선수는 404)
enum SportsImageURL {
    static func teamLogo(_ code: String) -> URL? {
        URL(string: "https://sports-phinf.pstatic.net/team/kbo/default/\(code).png")
    }

    static func player(_ playerId: String) -> URL? {
        URL(string: "https://sports-phinf.pstatic.net/player/kbo/default/\(playerId).png")
    }
}

/// 받은 이미지를 메모리와 기기 캐시 폴더에 보관한다 (앱 번들·저장소에는 넣지 않는다)
@MainActor
final class RemoteImageStore {
    static let shared = RemoteImageStore()

    private let memory = NSCache<NSURL, UIImage>()
    /// 없는 이미지(404)는 다시 요청하지 않는다
    private var missing = Set<URL>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        if missing.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }

        let file = directory.appendingPathComponent(Self.fileName(for: url))
        let task = Task<UIImage?, Never> {
            // 일주일 안에 받은 파일은 그대로 쓴다
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < 7 * 24 * 60 * 60,
               let image = UIImage(contentsOfFile: file.path) {
                return image
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    self.missing.insert(url)
                    return nil
                }
                guard let image = UIImage(data: data) else { return nil }
                try? data.write(to: file, options: .atomic)
                return image
            } catch {
                // 오프라인이면 오래된 파일이라도 쓴다
                return UIImage(contentsOfFile: file.path)
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }

    private static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

/// 주소의 이미지를 보여 주고, 받기 전이나 없으면 placeholder
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = RemoteImageStore.shared.cached(url)
            if image == nil {
                image = await RemoteImageStore.shared.image(for: url)
            }
        }
    }
}
