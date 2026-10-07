import Foundation

public struct LogoBrand: Identifiable, Sendable {
    public var id: String { domain }
    public let name: String
    public let domain: String
    public let aliases: [String]

    public static let common: [LogoBrand] = [
        .init(name: "American Express", domain: "www.americanexpress.com", aliases: ["Amex"]),
        .init(name: "Crédit Agricole", domain: "www.credit-agricole.it", aliases: ["Credit Agricole"]),
        .init(name: "Intesa Sanpaolo", domain: "www.intesasanpaolo.com", aliases: ["Intesa", "San Paolo"]),
        .init(name: "Revolut", domain: "www.revolut.com", aliases: []),
        .init(name: "UniCredit", domain: "www.unicredit.it", aliases: []),
        .init(name: "Fineco", domain: "finecobank.com", aliases: ["FinecoBank"]),
        .init(name: "N26", domain: "n26.com", aliases: []),
        .init(name: "ING", domain: "www.ing.it", aliases: ["Conto Arancio"]),
        .init(name: "Poste Italiane", domain: "www.poste.it", aliases: ["Postepay", "BancoPosta"]),
        .init(name: "BPER", domain: "www.bper.it", aliases: []),
        .init(name: "Banca Sella", domain: "www.sella.it", aliases: ["Sella"]),
        .init(name: "Nexi", domain: "www.nexi.it", aliases: []),
        .init(name: "Visa", domain: "www.visa.it", aliases: []),
        .init(name: "Mastercard", domain: "www.mastercard.it", aliases: []),
        .init(name: "PayPal", domain: "www.paypal.com", aliases: []),
        .init(name: "Wise", domain: "wise.com", aliases: [])
    ]

    public static func matching(_ query: String) -> [LogoBrand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return common }
        return common.filter { brand in
            ([brand.name, brand.domain] + brand.aliases).contains { $0.localizedStandardContains(query) }
        }
    }
}

public struct WebsiteLogo: Identifiable, Sendable {
    public var id: URL { source }
    public let source: URL
    public let data: Data
}

public struct LogoWebResponse: Sendable {
    public let data: Data
    public let url: URL
    public let contentType: String
    public init(data: Data, url: URL, contentType: String) {
        self.data = data; self.url = url; self.contentType = contentType
    }
}

/// No key, paid provider, search engine scraping, or server. Fetches only public site metadata and images.
public actor WebsiteLogoService {
    public static let shared = WebsiteLogoService()
    public enum Failure: Error { case invalidSite, invalidResponse, tooLarge, noImages }
    public typealias Download = @Sendable (URL, Int) async throws -> LogoWebResponse
    private let download: Download
    private var cache: [URL: [WebsiteLogo]] = [:]

    public init(download: @escaping Download = WebsiteLogoService.download) { self.download = download }

    public static func siteURL(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: value), isPublicHTTPS(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/"; components.query = nil; components.fragment = nil
        return components.url
    }

    public static func isPublicHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !host.hasSuffix(".internal"), !host.contains(":"),
              !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        return host.split(separator: ".").allSatisfy { label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-") &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    public func logos(for input: String) async throws -> [WebsiteLogo] {
        guard let site = Self.siteURL(input) else { throw Failure.invalidSite }
        if let result = cache[site] { return result }
        var urls: [URL] = []
        do {
            let page = try await download(site, 2 * 1024 * 1024)
            guard Self.isPublicHTTPS(page.url), page.data.count <= 2 * 1024 * 1024 else { throw Failure.invalidResponse }
            if page.contentType.contains("html"), let html = String(data: page.data, encoding: .utf8) {
                urls = Self.imageURLs(html: html, page: page.url)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            // Some sites block homepage requests but still publish browser icons.
        }
        urls += [site.appendingPathComponent("apple-touch-icon.png"), site.appendingPathComponent("favicon.ico")]
        var seen = Set<URL>()
        urls = urls.filter { Self.isPublicHTTPS($0) && seen.insert($0).inserted }.prefix(8).map { $0 }
        var results: [WebsiteLogo] = []
        // At most three connections at a time; cancellation propagates to every download.
        for start in stride(from: 0, to: urls.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(urls[start..<min(start + 3, urls.count)])
            let images = await withTaskGroup(of: WebsiteLogo?.self, returning: [WebsiteLogo].self) { group in
                for url in batch {
                    group.addTask { [download] in
                        do {
                            let response = try await download(url, 4 * 1024 * 1024)
                            guard Self.isPublicHTTPS(response.url), response.data.count <= 4 * 1024 * 1024 else { return nil }
                            let bytes = try AccountLogoImage.normalize(response.data)
                            try Task.checkCancellation()
                            return WebsiteLogo(source: url, data: bytes)
                        } catch { return nil }
                    }
                }
                var images: [WebsiteLogo] = []
                for await image in group { if let image { images.append(image) } }
                return images
            }
            for url in batch {
                if let image = images.first(where: { $0.source == url }), !results.contains(where: { $0.data == image.data }) {
                    results.append(image)
                }
            }
            if results.count >= 4 { break }
        }
        try Task.checkCancellation()
        guard !results.isEmpty else { throw Failure.noImages }
        if cache.count >= 12 { cache.removeAll() }
        cache[site] = Array(results.prefix(4))
        return Array(results.prefix(4))
    }

    public static func imageURLs(html: String, page: URL) -> [URL] {
        guard html.utf8.count <= 2 * 1024 * 1024,
              let tags = try? NSRegularExpression(pattern: #"<(link|img)\b[^>]*>"#, options: [.caseInsensitive]),
              let attributes = try? NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [] }
        let text = html as NSString
        var candidates: [(URL, Int, Int)] = []
        for (position, match) in tags.matches(in: html, range: NSRange(location: 0, length: text.length)).enumerated() {
            let tag = text.substring(with: match.range)
            let tagText = tag as NSString
            var fields: [String: String] = [:]
            for attribute in attributes.matches(in: tag, range: NSRange(location: 0, length: tagText.length)) {
                let name = tagText.substring(with: attribute.range(at: 1)).lowercased()
                for index in 2...4 where attribute.range(at: index).location != NSNotFound {
                    fields[name] = decodeEntities(tagText.substring(with: attribute.range(at: index)))
                }
            }
            let relation = (fields["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            let isLink = text.substring(with: match.range(at: 1)).lowercased() == "link"
            let path: String?
            let priority: Int
            if isLink, relation.contains("apple-touch-icon") || relation.contains("apple-touch-icon-precomposed") {
                path = fields["href"]; priority = 100
            } else if isLink, relation.contains("icon") {
                path = fields["href"]; priority = 90
            } else if !isLink, ((fields["alt"] ?? "") + " " + (fields["src"] ?? "")).localizedCaseInsensitiveContains("logo") {
                path = fields["src"] ?? fields["data-src"]; priority = 80
            } else { continue }
            guard let path, let url = URL(string: path, relativeTo: page)?.absoluteURL,
                  Self.isPublicHTTPS(url), url.pathExtension.lowercased() != "svg" else { continue }
            candidates.append((url, priority, position))
        }
        var seen = Set<URL>()
        return candidates.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }
            .map(\.0).filter { seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else { return value }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value), let numberRange = Range(match.range(at: 1), in: value) else { continue }
            let number = String(value[numberRange])
            let integer = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
            if let integer, let scalar = UnicodeScalar(integer) { value.replaceSubrange(range, with: String(scalar)) }
        }
        return value
    }

    public static func download(_ url: URL, limit: Int) async throws -> LogoWebResponse {
        guard isPublicHTTPS(url) else { throw Failure.invalidSite }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: LogoRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Formi/1.0 (website icon lookup)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let finalURL = response.url, isPublicHTTPS(finalURL) else { throw Failure.invalidResponse }
        guard response.expectedContentLength <= Int64(limit) else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw Failure.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return LogoWebResponse(data: data, url: finalURL, contentType: response.mimeType ?? "")
    }
}

private final class LogoRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(WebsiteLogoService.isPublicHTTPS) == true ? request : nil)
    }
}
