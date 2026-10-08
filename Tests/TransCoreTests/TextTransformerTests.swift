import XCTest
import TransCore

final class TextTransformerTests: XCTestCase {
    // MARK: - Variants

    func testFourVariantsOfASentence() {
        let text = "Привет, мир! Как дела?"
        XCTAssertEqual(TextTransformer.apply(text, mode: .original), text)
        XCTAssertEqual(TextTransformer.apply(text, mode: .originalNoPunctuation), "Привет мир Как дела")
        XCTAssertEqual(TextTransformer.apply(text, mode: .lowercase), "привет, мир! как дела?")
        XCTAssertEqual(TextTransformer.apply(text, mode: .lowercaseNoPunctuation), "привет мир как дела")
    }

    func testJoinersAndNumbersStay() {
        XCTAssertEqual(TextTransformer.apply("Что-то стоит 3.5 рубля, в 10:30 — don't (честно).", mode: .originalNoPunctuation),
                       "Что-то стоит 3.5 рубля в 10:30 don't честно")
        XCTAssertEqual(TextTransformer.apply("Т-34, 1,5 литра", mode: .lowercaseNoPunctuation), "т-34 1,5 литра")
    }

    func testMarksBetweenWordsLeaveOneSpace() {
        XCTAssertEqual(TextTransformer.apply("слово,слово…слово", mode: .originalNoPunctuation), "слово слово слово")
        XCTAssertEqual(TextTransformer.apply("«Цитата» и (скобки) - вот", mode: .originalNoPunctuation), "Цитата и скобки вот")
        XCTAssertEqual(TextTransformer.apply("Да?! Нет...", mode: .originalNoPunctuation), "Да Нет")
    }

    func testLinesAndRepliesStay() {
        XCTAssertEqual(TextTransformer.apply("Первый абзац. Конец!\n\nВторой, абзац.", mode: .lowercaseNoPunctuation),
                       "первый абзац конец\n\nвторой абзац")
        XCTAssertEqual(TextTransformer.apply("— Привет!\n— Пока.", mode: .originalNoPunctuation), "Привет\nПока")
    }

    func testSpacingWithoutMarksIsKept() {
        XCTAssertEqual(TextTransformer.apply("Два  пробела ", mode: .originalNoPunctuation), "Два  пробела ")
        XCTAssertEqual(TextTransformer.apply("ЁЖ ПРОПИСНЫЕ", mode: .lowercase), "ёж прописные")
    }

    // MARK: - Formats

    func testTimecodesKeepTheirTimes() {
        let text = "[01:23] Привет, мир.\n[1:01:05] — Да!"
        XCTAssertEqual(TranscriptFormat.timecodes.apply(.lowercaseNoPunctuation, to: text), "[01:23] привет мир\n[1:01:05] да")
        XCTAssertEqual(TranscriptFormat.timecodes.apply(.lowercase, to: text), "[01:23] привет, мир.\n[1:01:05] — да!")
    }

    func testSubtitlesKeepNumbersAndTimes() {
        let srt = "1\n00:00:01,000 --> 00:00:02,500\nПривет, мир.\n\n2\n00:00:03,000 --> 00:00:04,000\n— Да!\n"
        XCTAssertEqual(TranscriptFormat.srt.apply(.lowercaseNoPunctuation, to: srt),
                       "1\n00:00:01,000 --> 00:00:02,500\nпривет мир\n\n2\n00:00:03,000 --> 00:00:04,000\nда\n")
        XCTAssertEqual(TranscriptFormat.srt.apply(.original, to: srt), srt)
    }

    func testRenderedFormats() {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "Привет, мир."),
            TranscriptSegment(start: 4, end: 6, text: "Как дела?"),
        ]
        let mode = TextCaseMode.lowercaseNoPunctuation
        XCTAssertEqual(TranscriptFormat.text.apply(mode, to: TranscriptFormat.text.render(segments)), "привет мир\n\nкак дела")
        XCTAssertEqual(TranscriptFormat.timecodes.apply(mode, to: TranscriptFormat.timecodes.render(segments)),
                       "[00:00] привет мир\n[00:04] как дела")
        XCTAssertEqual(TranscriptFormat.srt.apply(mode, to: TranscriptFormat.srt.render(segments)),
                       "1\n00:00:00,000 --> 00:00:02,000\nпривет мир\n\n2\n00:00:04,000 --> 00:00:06,000\nкак дела\n")
    }

    // MARK: - Edits under a variant

    private func merge(_ edited: String, into text: String, _ mode: TextCaseMode,
                       _ format: TranscriptFormat = .text) -> String {
        format.merge(edited, into: text, mode: mode)
    }

    func testEditWithoutVariantIsTakenAsIs() {
        XCTAssertEqual(merge("Новый текст", into: "Старый текст", .original), "Новый текст")
    }

    func testUnchangedTextStays() {
        let text = "— Привет, Мир!\n\n«Цитата» и (скобки)."
        for mode in TextCaseMode.allCases {
            XCTAssertEqual(merge(TranscriptFormat.text.apply(mode, to: text), into: text, mode), text, "\(mode)")
        }
    }

    func testFixedWordKeepsCapitalsAround() {
        XCTAssertEqual(merge("привет, мир.", into: "Превет, Мир.", .lowercase), "Привет, Мир.")
    }

    func testEditsKeepHiddenMarks() {
        let text = "Привет, мир."
        XCTAssertEqual(merge("Привет дорогой мир", into: text, .originalNoPunctuation), "Привет, дорогой мир.")
        XCTAssertEqual(merge("Приветик мир", into: text, .originalNoPunctuation), "Приветик, мир.")
        XCTAssertEqual(merge("Привет миру", into: text, .originalNoPunctuation), "Привет, миру.")
        XCTAssertEqual(merge("Привет друг", into: text, .originalNoPunctuation), "Привет, друг.")
        XCTAssertEqual(merge("Приветмир", into: text, .originalNoPunctuation), "Приветмир.")
    }

    func testSpaceTypedAtTheEndOfALineStays() {
        var text = "Привет, мир."
        text = merge("Привет мир ", into: text, .originalNoPunctuation)
        XCTAssertEqual(text, "Привет, мир. ")
        XCTAssertEqual(TextTransformer.apply(text, mode: .originalNoPunctuation), "Привет мир ")
        text = merge("Привет мир и", into: text, .originalNoPunctuation)
        XCTAssertEqual(text, "Привет, мир. и")
        XCTAssertEqual(merge("Привет мир у и", into: "Привет, мир.", .originalNoPunctuation), "Привет, мир. у и")
        XCTAssertEqual(merge("Привет миру и", into: "Привет, мир.", .originalNoPunctuation), "Привет, миру и.")
    }

    func testTypingAtTheStartOfAReply() {
        XCTAssertEqual(merge("Ну привет\nпока", into: "— Привет!\n— Пока.", .lowercaseNoPunctuation), "— Ну Привет!\n— Пока.")
    }

    func testTypedMarksAndCapitalsAreKeptButNotShown() {
        let text = merge("Привет, мир", into: "Привет мир", .originalNoPunctuation)
        XCTAssertEqual(text, "Привет, мир")
        XCTAssertEqual(TextTransformer.apply(text, mode: .originalNoPunctuation), "Привет мир")
        let lowered = merge("привет Мир", into: "привет", .lowercase)
        XCTAssertEqual(lowered, "привет Мир")
        XCTAssertEqual(TextTransformer.apply(lowered, mode: .lowercase), "привет мир")
    }

    func testOtherVariantsShowTheEdit() {
        let text = merge("привет дорогой мир", into: "Привет, мир.", .lowercaseNoPunctuation)
        XCTAssertEqual(TextTransformer.apply(text, mode: .original), "Привет, дорогой мир.")
        XCTAssertEqual(TextTransformer.apply(text, mode: .lowercase), "привет, дорогой мир.")
    }

    func testEditsOfSubtitlesAndTimecodes() {
        let srt = "1\n00:00:01,000 --> 00:00:02,500\nПривет, Мир.\n"
        let shown = TranscriptFormat.srt.apply(.lowercaseNoPunctuation, to: srt)
        let edited = shown.replacingOccurrences(of: "мир", with: "друг")
        XCTAssertEqual(merge(edited, into: srt, .lowercaseNoPunctuation, .srt), "1\n00:00:01,000 --> 00:00:02,500\nПривет, друг.\n")

        let timecodes = "[00:01] — Да, конечно.\n[00:05] Нет!"
        let edit = TranscriptFormat.timecodes.apply(.originalNoPunctuation, to: timecodes)
            .replacingOccurrences(of: "конечно", with: "разумеется")
        XCTAssertEqual(merge(edit, into: timecodes, .originalNoPunctuation, .timecodes), "[00:01] — Да, разумеется.\n[00:05] Нет!")
    }

    func testReplaceAllChangesOnlyTheWords() {
        let text = "Превет, Анна. Как дела? Превет, Борис!"
        let shown = TextTransformer.apply(text, mode: .lowercaseNoPunctuation)
        let edited = shown.replacingOccurrences(of: "превет", with: "привет")
        XCTAssertEqual(merge(edited, into: text, .lowercaseNoPunctuation), "Привет, Анна. Как дела? Привет, Борис!")
    }

    // MARK: - Random edits

    /// A small fixed generator, so a failure repeats.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11 ^ state
        }
    }

    private static let letters = Array("абвгдеёжзиклмнопрстуфхцчшщыэюяАБВГДЕЖЗИКЛМНОПРСТУФХЦЧЭЮЯabcdefxyzABCXYZ")
    private static let alphabet = letters + Array("     ..,,!?—–-'’«»\"():;…\n")

    private func randomText(_ generator: inout Generator) -> String {
        String((0..<Int.random(in: 0...60, using: &generator)).map { _ in Self.alphabet.randomElement(using: &generator)! })
    }

    /// A letter typed anywhere shows up exactly where it was typed, in every variant and format.
    func testTypedLetterShowsWhereTyped() {
        var generator = Generator(state: 42)
        for _ in 0..<3000 {
            let text = randomText(&generator)
            let mode = TextCaseMode.allCases.randomElement(using: &generator)!
            let format = TranscriptFormat.allCases.randomElement(using: &generator)!
            var shown = Array(format.apply(mode, to: text))
            shown.insert(Self.letters.randomElement(using: &generator)!, at: Int.random(in: 0...shown.count, using: &generator))
            let edited = String(shown)
            let merged = format.merge(edited, into: text, mode: mode)
            XCTAssertEqual(format.apply(mode, to: merged), format.apply(mode, to: edited),
                           "\(mode) \(format): \(text.debugDescription) → \(edited.debugDescription)")
        }
    }

    /// Any edit is taken without a crash, and an edit that keeps the shown text keeps the text.
    func testRandomEdits() {
        var generator = Generator(state: 7)
        for _ in 0..<3000 {
            let text = randomText(&generator)
            let mode = TextCaseMode.allCases.randomElement(using: &generator)!
            let format = TranscriptFormat.allCases.randomElement(using: &generator)!
            let shown = Array(format.apply(mode, to: text))
            var edited = shown
            let start = Int.random(in: 0...edited.count, using: &generator)
            let end = Int.random(in: start...min(edited.count, start + 8), using: &generator)
            edited.replaceSubrange(start..<end, with: Array(randomText(&generator).prefix(Int.random(in: 0...6, using: &generator))))
            _ = format.merge(String(edited), into: text, mode: mode)
            XCTAssertEqual(format.merge(String(shown), into: text, mode: mode), text)
        }
    }

    func testLongTextIsQuick() {
        let paragraph = "Привет, мир! Это длинная расшифровка — с репликами, «кавычками» и числами 3.5 и 10:30.\n\n"
        let text = String(repeating: paragraph, count: 1500)
        measure {
            let shown = TextTransformer.apply(text, mode: .lowercaseNoPunctuation)
            var edited = Array(shown)
            edited.insert("я", at: edited.count / 2)
            _ = TextTransformer.merge(String(edited), into: text, mode: .lowercaseNoPunctuation)
        }
    }
}
