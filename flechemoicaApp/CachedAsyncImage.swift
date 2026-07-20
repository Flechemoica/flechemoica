import Combine
import CryptoKit
import SwiftUI
import UIKit

struct CachedAsyncImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @StateObject private var loader = CachedRemoteImageLoader()

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else if loader.didFail {
                failure()
            } else {
                placeholder()
                    .task(id: url) {
                        await loader.load(url: url)
                    }
            }
        }
    }
}

@MainActor
private final class CachedRemoteImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private var loadedURL: URL?

    func load(url: URL) async {
        guard loadedURL != url else { return }

        loadedURL = url
        didFail = false
        image = nil

        do {
            image = try await RemoteImageDiskCache.shared.image(for: url)
        } catch {
            didFail = true
        }
    }
}

private actor RemoteImageDiskCache {
    static let shared = RemoteImageDiskCache()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("FlecheMoicaImageCache", isDirectory: true)
    }

    func image(for url: URL) async throws -> UIImage {
        try prepareCacheDirectory()

        let fileURL = cacheFileURL(for: url)

        if let cachedImage = UIImage(contentsOfFile: fileURL.path) {
            return cachedImage
        }

        let data = try await downloadImageData(from: url)

        guard let image = UIImage(data: data) else {
            throw RemoteImageDiskCacheError.invalidImageData
        }

        try data.write(to: fileURL, options: [.atomic])
        return image
    }

    private func prepareCacheDirectory() throws {
        guard !fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let fileExtension = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return cacheDirectory.appendingPathComponent("\(key).\(fileExtension)")
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        guard url.scheme == "https" || url.scheme == "http" else {
            throw RemoteImageDiskCacheError.unsupportedURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteImageDiskCacheError.badResponse
        }

        return data
    }
}

private enum RemoteImageDiskCacheError: Error {
    case unsupportedURL
    case badResponse
    case invalidImageData
}
