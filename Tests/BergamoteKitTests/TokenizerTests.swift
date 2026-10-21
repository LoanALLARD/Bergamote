import Foundation
import Testing
@testable import BergamoteKit

@Suite("Tokenizer Unigram")
struct TokenizerTests {
    /// Vocabulaire minimal au format 🤗 tokenizers, avec les identifiants spéciaux de CamemBERT.
    static let tinyVocabulary = """
        {
          "added_tokens": [
            {"id": 0, "content": "<s>NOTUSED"}, {"id": 1, "content": "<pad>"}, {"id": 2, "content": "</s>NOTUSED"},
            {"id": 3, "content": "<unk>"}, {"id": 5, "content": "<s>"}, {"id": 6, "content": "</s>"}
          ],
          "model": {
            "type": "Unigram", "unk_id": 3,
            "vocab": [
              ["<s>NOTUSED", 0.0], ["<pad>", 0.0], ["</s>NOTUSED", 0.0], ["<unk>", 0.0], ["<unk>NOTUSED", -100.0],
              ["<s>", 0.0], ["</s>", 0.0],
              ["▁fact", -3.0], ["ure", -3.0], ["▁facture", -4.0], ["s", -2.0], ["▁", -1.0],
              ["f", -6.0], ["a", -6.0], ["c", -6.0], ["t", -6.0], ["u", -6.0], ["r", -6.0], ["e", -6.0]
            ]
          }
        }
        """

    @Test func viterbiPrefersMostProbableSegmentation() throws {
        let tokenizer = try UnigramTokenizer(data: Data(Self.tinyVocabulary.utf8))
        // « ▁facture » (−4) bat « ▁fact » + « ure » (−6).
        #expect(tokenizer.encode("factures") == [5, 9, 10, 6])
        #expect(tokenizer.bosID == 5 && tokenizer.eosID == 6 && tokenizer.padID == 1)
    }

    @Test func unknownCharactersCollapseIntoOneUnk() throws {
        let tokenizer = try UnigramTokenizer(data: Data(Self.tinyVocabulary.utf8))
        #expect(tokenizer.encode("€€€") == [5, 11, 3, 6])
    }

    @Test func truncatesToSequenceLength() throws {
        let tokenizer = try UnigramTokenizer(data: Data(Self.tinyVocabulary.utf8))
        let ids = tokenizer.encode(String(repeating: "facture ", count: 50), maxLength: 8)
        #expect(ids.count == 8)
        #expect(ids.first == 5 && ids.last == 6)
    }

    /// Parité avec 🤗 tokenizers sur le vrai vocabulaire CamemBERT. Le jeu de référence est produit
    /// par `scripts/convert_camembert.py` (ou `scripts/tokenizer_fixture.py`) ; le test est ignoré
    /// si `BERGAMOTE_TOKENIZER_DIR` n'est pas défini.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BERGAMOTE_TOKENIZER_DIR"] != nil))
    func matchesHuggingFaceOnCamembertVocabulary() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BERGAMOTE_TOKENIZER_DIR"]!)
        let tokenizer = try UnigramTokenizer(contentsOf: directory.appendingPathComponent("tokenizer.json"))
        let fixture = try JSONDecoder().decode(
            [Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("tokenizer_fixture.json")))
        #expect(!fixture.isEmpty)
        for sample in fixture {
            #expect(tokenizer.encode(sample.text, maxLength: 256) == sample.ids, "\(sample.text)")
        }
    }

    struct Fixture: Decodable {
        let text: String
        let ids: [Int]
    }
}
