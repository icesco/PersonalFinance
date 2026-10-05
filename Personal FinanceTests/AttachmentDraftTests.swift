import Foundation
import Testing
@testable import Personal_Finance

struct AttachmentDraftTests {
    @Test func validatesContentAndSizeBeforePersistence() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let draft = try AttachmentDraft(filename: "scontrino.png", data: png)
        #expect(draft.contentType == "public.png")
        #expect(draft.data == png)
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "vuoto.png", data: Data()) }
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "falso.jpg", data: Data("non immagine".utf8)) }
        #expect(throws: (any Error).self) { try AttachmentDraft(filename: "grande.pdf", data: Data(repeating: 0, count: 10 * 1024 * 1024 + 1)) }
    }
}
