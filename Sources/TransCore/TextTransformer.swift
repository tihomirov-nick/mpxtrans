import Foundation

/// The four case and punctuation variants of the transcript, the same as in Subline's style.
public enum TextCaseMode: String, CaseIterable, Identifiable, Sendable {
    /// Upper and lower case, with punctuation
    case original
    /// Upper and lower case, without punctuation
    case originalNoPunctuation
    /// Lower case only, with punctuation
    case lowercase
    /// Lower case only, without punctuation
    case lowercaseNoPunctuation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: return L("Заглавные и строчные, со знаками препинания")
        case .originalNoPunctuation: return L("Заглавные и строчные, без знаков препинания")
        case .lowercase: return L("Все строчные, со знаками препинания")
        case .lowercaseNoPunctuation: return L("Все строчные, без знаков препинания")
        }
    }

    public var shortTitle: String {
        switch self {
        case .original: return L("Аа  ,.!?")
        case .originalNoPunctuation: return L("Аа")
        case .lowercase: return L("аа  ,.!?")
        case .lowercaseNoPunctuation: return L("аа")
        }
    }

    public var removesPunctuation: Bool { self == .originalNoPunctuation || self == .lowercaseNoPunctuation }
    public var lowercases: Bool { self == .lowercase || self == .lowercaseNoPunctuation }
}

/// Applies a case and punctuation variant to transcript text, by Subline's rules. The text stays editable under any
/// variant: lines and the spacing the user typed are kept (only the spaces around a removed mark are tidied up),
/// and `merge` carries an edit of the shown text back into the text it was shown from.
public enum TextTransformer {
    private static let russian = Locale(identifier: "ru_RU")

    /// Characters removed in the "without punctuation" variants.
    private static let punctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "…", "\"", "'", "«", "»", "„", "“", "”", "‟", "‘", "’", "‚",
        "(", ")", "[", "]", "{", "}", "<", ">", "‹", "›", "—", "–", "―", "‒", "-", "‐", "‑", "¡", "¿", "*", "_",
    ]
    /// Kept when they join two letters or digits: "что-то", "don't", "д'Артаньян".
    private static let joiners: Set<Character> = ["-", "‐", "‑", "'", "’"]
    /// Kept between digits: "3.5", "1,5", "10:30".
    private static let numberSeparators: Set<Character> = [".", ",", ":"]
    /// An edit spread over a longer stretch of text is taken as one replacement: comparing such stretches
    /// character by character would take too long.
    private static let longestCompared = 4000

    /// `text` in the variant. `kept` tells how many first characters of a line are not speech and stay as they are.
    public static func apply(_ text: String, mode: TextCaseMode, kept: (ArraySlice<Character>) -> Int = { _ in 0 }) -> String {
        guard mode != .original else { return text }
        return String(shown(Array(text), mode: mode, kept: kept).chars)
    }

    /// The text after an edit of its variant: `edited` is `apply(text, mode:)` with the user's changes. They go to
    /// the same places of `text`, so capitals and marks stay wherever the user did not touch the text and show again
    /// in the other variants; what the user typed is kept as typed.
    public static func merge(_ edited: String, into text: String, mode: TextCaseMode,
                             kept: (ArraySlice<Character>) -> Int = { _ in 0 }) -> String {
        guard mode != .original else { return edited }
        let source = Array(text)
        let shown = shown(source, mode: mode, kept: kept)
        let old = shown.chars, new = Array(edited)
        guard old != new else { return text }

        // The changed stretch, then what exactly changed in it: one stretch for typing, several for Replace All.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        var removed = Set(prefix..<old.count - suffix)
        var inserted = Set(prefix..<new.count - suffix)
        if removed.count + inserted.count <= longestCompared {
            removed = []
            inserted = []
            let changes = Array(new[prefix..<new.count - suffix]).difference(from: Array(old[prefix..<old.count - suffix]))
            for change in changes {
                switch change {
                case .remove(let offset, _, _): removed.insert(prefix + offset)
                case .insert(let offset, _, _): inserted.insert(prefix + offset)
                }
            }
        }

        var result: [Character] = []
        result.reserveCapacity(source.count + new.count - old.count)
        var copied = 0  // characters of the source dealt with
        var replacing = false  // after removed characters: typed ones take their place
        var typing = false  // inside typed text, its place is chosen
        func copy(to end: Int) {
            guard end > copied else { return }
            result += source[copied..<end]
            copied = end
        }
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) || j >= new.count {
                // Marks hidden between two removed characters go with them.
                if replacing {
                    copied = max(copied, shown.origins[i].lowerBound)
                } else {
                    copy(to: shown.origins[i].lowerBound)
                }
                copied = max(copied, shown.origins[i].upperBound)
                replacing = true
                i += 1
            } else if j < new.count, inserted.contains(j) || i >= old.count {
                // Typed text goes right after the character before it ("мир." with "у" typed after "мир" becomes
                // "миру."), and after the marks hidden around it in two cases: when it starts with a space at the
                // end of a line ("мир." becomes "мир. ", so the space stays in sight) and at the start of a line
                // ("— Привет" stays a reply).
                if !replacing, !typing {
                    let lineEnd = i >= old.count || old[i].isNewline
                    if lineEnd, new[j].isWhitespace {
                        copy(to: i < old.count ? shown.origins[i].lowerBound : source.count)
                    } else if !lineEnd, shown.speechAfterMarks.contains(shown.origins[i].lowerBound) {
                        copy(to: shown.origins[i].lowerBound)
                    }
                }
                typing = true
                result.append(new[j])
                j += 1
            } else {
                copy(to: shown.origins[i].upperBound)
                replacing = false
                typing = false
                i += 1
                j += 1
            }
        }
        copy(to: source.count)
        return String(result)
    }

    /// The variant and, for each of its characters, the characters of the source it stands for: one character, or
    /// a run of spaces and marks for the space left in their place. Removed characters stand for nothing.
    struct Shown {
        var chars: [Character] = []
        var origins: [Range<Int>] = []
        /// Where a line's speech begins after marks hidden at its start ("— Привет").
        var speechAfterMarks: Set<Int> = []

        mutating func append(_ char: Character, _ origin: Range<Int>) {
            chars.append(char)
            origins.append(origin)
        }
    }

    static func shown(_ source: [Character], mode: TextCaseMode, kept: (ArraySlice<Character>) -> Int) -> Shown {
        var out = Shown()
        out.chars.reserveCapacity(source.count)
        out.origins.reserveCapacity(source.count)
        var lineStart = 0
        while lineStart <= source.count {
            var lineEnd = lineStart
            while lineEnd < source.count, !source[lineEnd].isNewline { lineEnd += 1 }
            let speech = lineStart + min(max(0, kept(source[lineStart..<lineEnd])), lineEnd - lineStart)
            for k in lineStart..<speech { out.append(source[k], k..<k + 1) }
            if mode.removesPunctuation {
                removePunctuation(source, speech..<lineEnd, into: &out)
            } else {
                for k in speech..<lineEnd { out.append(source[k], k..<k + 1) }
            }
            if lineEnd < source.count { out.append(source[lineEnd], lineEnd..<lineEnd + 1) }
            lineStart = lineEnd + 1
        }
        if mode.lowercases { lowercase(&out) }
        return out
    }

    /// Removes the marks of one line's speech. A run of marks and spaces becomes one space between words
    /// ("слово, слово" and "слово,слово" give "слово слово") and nothing at the start of the line; spaces without
    /// marks stay as they are.
    private static func removePunctuation(_ source: [Character], _ part: Range<Int>, into out: inout Shown) {
        func removable(_ k: Int) -> Bool {
            let c = source[k]
            guard punctuation.contains(c) else { return false }
            let prev: Character? = k > part.lowerBound ? source[k - 1] : nil
            let next: Character? = k + 1 < part.upperBound ? source[k + 1] : nil
            if joiners.contains(c), let p = prev, let n = next, isWordChar(p), isWordChar(n) { return false }
            if numberSeparators.contains(c), let p = prev, let n = next, p.isNumber, n.isNumber { return false }
            return true
        }
        var k = part.lowerBound
        while k < part.upperBound {
            guard source[k].isWhitespace || removable(k) else {
                out.append(source[k], k..<k + 1)
                k += 1
                continue
            }
            let start = k
            var marks = false, spaces = false
            while k < part.upperBound, source[k].isWhitespace || removable(k) {
                if source[k].isWhitespace { spaces = true } else { marks = true }
                k += 1
            }
            if !marks {
                for s in start..<k { out.append(source[s], s..<s + 1) }
            } else if start == part.lowerBound {
                // "— Привет": the dash of a reply goes together with the space after it.
                out.speechAfterMarks.insert(k)
            } else if k == part.upperBound {
                // A space typed after the last mark of a line stays: the next word is on its way.
                if spaces, source[k - 1].isWhitespace { out.append(" ", start..<k) }
            } else if spaces || (isWordChar(source[start - 1]) && isWordChar(source[k])) {
                out.append(" ", start..<k)
            }
        }
    }

    private static func lowercase(_ out: inout Shown) {
        let lowered = Array(String(out.chars).lowercased(with: russian))
        if lowered.count == out.chars.count {
            out.chars = lowered
            return
        }
        // A letter that turns into several characters (rare): one at a time, so the origins stay right.
        var chars: [Character] = [], origins: [Range<Int>] = []
        for (char, origin) in zip(out.chars, out.origins) {
            for lowerChar in String(char).lowercased(with: russian) {
                chars.append(lowerChar)
                origins.append(origin)
            }
        }
        out.chars = chars
        out.origins = origins
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }
}

extension TranscriptFormat {
    /// The transcript in a case and punctuation variant: only what was said changes, the times in front of lines
    /// ("[01:23]") and the numbers and times of subtitles stay as they are.
    public func apply(_ mode: TextCaseMode, to text: String) -> String {
        TextTransformer.apply(text, mode: mode, kept: notSpeech)
    }

    /// The transcript after an edit of its variant (see `TextTransformer.merge`).
    public func merge(_ edited: String, into text: String, mode: TextCaseMode) -> String {
        TextTransformer.merge(edited, into: text, mode: mode, kept: notSpeech)
    }

    /// How many first characters of a line are not speech.
    private func notSpeech(_ line: ArraySlice<Character>) -> Int {
        switch self {
        case .text:
            return 0
        case .timecodes:
            // "[01:23] " or "[1:01:23] "
            guard line.first == "[", let close = line.firstIndex(of: "]") else { return 0 }
            let time = line[(line.startIndex + 1)..<close]
            guard time.contains(":"), time.count <= 10, time.allSatisfy({ $0 == ":" || ("0"..."9").contains($0) }) else { return 0 }
            let end = close + 1 < line.endIndex && line[close + 1] == " " ? close + 2 : close + 1
            return end - line.startIndex
        case .srt:
            // "00:01:02,345 --> 00:01:04,000"; numbers have no letters or marks to change.
            return String(line).contains("-->") ? line.count : 0
        }
    }
}
