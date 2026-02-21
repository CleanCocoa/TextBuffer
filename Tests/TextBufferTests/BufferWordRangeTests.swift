//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

/// Shoveling-operator for dictionary concatenation or merging.
fileprivate func << <Key, Value>(
    lhs: inout [Key: Value],
    rhs: [Key: Value]
) {
    lhs = lhs.merging(rhs) { _, rhs in
        rhs
    }
}

final class BufferWordRangeTests: XCTestCase {
    func word(punctuatedBy char: Character) -> [String : String] {
        return word(punctuatedBy: char, char)
    }

    func word(punctuatedBy lhs: Character, _ rhs: Character) -> [String : String] {
        var samples: [String : String] = [:]

        func addPair(_ lhs: Character, _ rhs: Character) {
            samples << [
                "a punc\(lhs)tuˇat\(rhs)ion z" : "a punc\(lhs)«tuat»\(rhs)ion z",
                "a punc\(lhs)t«ua»t\(rhs)ion z"  : "a punc\(lhs)«tuat»\(rhs)ion z",
                "a punc\(lhs)«tuat»\(rhs)ion z"  : "a punc\(lhs)«tuat»\(rhs)ion z",
            ]
        }

        addPair(lhs, rhs)
        addPair(" ", rhs)
        addPair(lhs, " ")

        return samples
    }

    func sanitized(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: -

extension BufferWordRangeTests {
    func testWordRange_ValidCases() throws {
        var samples: [String : String] = [:]
        samples << [ // Empty buffer maintains selection
            "ˇ"                    : "ˇ",
            "  ˇ  "                : "  ˇ  ",
            " \n\t ˇ \n\t "        : " \n\t ˇ \n\t ",
            " \n\t « \t\n » \n\t " : " \n\t « \t\n » \n\t ",
        ]
        samples << [ // Direct selection of adjacent, non-boundary word
            "aˇ"    : "«a»",
            "«a»"   : "«a»",
            "fooˇ"  : "«foo»",
            "«foo»" : "«foo»",
            "ˇfoo"  : "«foo»",
            "你ˇ"    : "«你»",
            "你好ˇ"  : "«你好»",
        ]
        samples << [ // Skipping whitespace to find next word forward
            "ˇ  \n\t\r  foo  " : "  \n\t\r  «foo»  ",
            "  \n\t\r  foo  ˇ" : "  \n\t\r  «foo»  ",
            "foo ˇ \n\t bar"   : "foo  \n\t «bar»",
            "你  ˇ  好"         : "你    «好»",
        ]
        samples << [ // Upstream selection affinity (towards beginning). Prioritize 'word' right before insertion point rather than lookahead, offsetting forward whitespace skipping.
            "(foo)ˇ bar"          : "«(foo)» bar",
            "(foo barf!?)ˇ baz"   : "(foo «barf!?)» baz",
            "(foo)«  »   bar"     : "«(foo)»     bar",  // "bar" is farther than "(foo)"
            "(foo)«  » bar"       : "«(foo)»   bar",    // bar is closer than "(foo)"
        ]
        samples << [ // Trim whitespace from selection
            "  «   foo   »  "           : "     «foo»     ",
            " foo  «  bar  »  baz  "    : " foo    «bar»    baz  ",
            " foo  «  bar !  »  baz  "  : " foo    «bar !»    baz  ",
            " foo  «  ba rr  »  baz  "  : " foo    «ba rr»    baz  ",
            " fo«o    ba rr  »  baz  "  : " «foo    ba rr»    baz  ",
        ]
        samples << [ // Selecting symbols, too, if that's all there is adjacent to insertion point
            "?ˇ"    : "«?»",
            "ˇ?"    : "«?»",
            "«?»"   : "«?»",
            "a!ˇ"   : "«a!»",
            "a«!»"  : "«a!»",
            "ˇ,b"   : "«,b»",
            "«,»b"  : "«,b»",
        ]
        samples << [ // Punctuation
            "ˇ(foo bar)" : "«(foo» bar)",
            "ˇ(foo) bar" : "«(foo)» bar",
            "(foo)ˇ bar" : "«(foo)» bar",
            "(foo bar)ˇ" : "(foo «bar)»",
            "foo (bar)ˇ" : "foo «(bar)»",
        ]
        samples << [ // Emoji ranges
            "⭐️ˇ"        : "«⭐️»",
            "⭐️ ⭐️ˇ"     : "⭐️ «⭐️»",
            "⭐️ «⭐️»"    : "⭐️ «⭐️»",
            // This is actually a skin-color changed female head, but Xcode renders this as a male head with female modifier
            "👴🏻 👱🏾‍♀️ˇ"  : "👴🏻 «👱🏾‍♀️»",
            "👴🏻 «👱🏾‍♀️»" : "👴🏻 «👱🏾‍♀️»",
        ]
        samples << [ // Select closest word or the one to the right
            "foo « »bar"  : "foo  «bar»",
            "foo« » bar"  : "«foo»  bar",
            "foo « » bar" : "foo   «bar»",
        ]
        for separator in [
            " ", "\t",
            "　", // IDEOGRAPHIC SPACE
            "\n", "\r", "\r\n"
        ] {
            samples << [
                "start word\(separator)wordˇ end"        : "start word\(separator)«word» end",
                "start word\(separator)ˇword end"        : "start word\(separator)«word» end",
                "start word\(separator)«word» end"       : "start word\(separator)«word» end",
                "start wordˇ\(separator)word end"        : "start «word»\(separator)word end",
                "start wo«rd\(separator)wo»rd end"       : "start «word\(separator)word» end",
                // Idempotency of word selection
                "start «word»\(separator)word end"       : "start «word»\(separator)word end",
                "start «word\(separator)word» end"       : "start «word\(separator)word» end",
                "start «two words»\(separator)word end"  : "start «two words»\(separator)word end",
            ]
        }
        samples << word(punctuatedBy: #"("#, #")"#)
        samples << word(punctuatedBy: #"["#, #"]"#)
        samples << word(punctuatedBy: #"〔"#, #"〕"#)
        samples << word(punctuatedBy: #"《"#, #"》"#)
        samples << word(punctuatedBy: #"."#)
        samples << word(punctuatedBy: #","#)
        samples << word(punctuatedBy: #"、"#) // IDEOGRAPHIC COMMA
        samples << word(punctuatedBy: #"。"#) // IDEOGRAPHIC PERIOD
        samples << word(punctuatedBy: #"､"#) // HALFWIDTH IDEOGRAPHIC COMMA
        samples << word(punctuatedBy: #"｡"#) // HALFWIDTH IDEOGRAPHIC PERIOD
        samples << word(punctuatedBy: #"¿"#, #"?"#)
        samples << word(punctuatedBy: #"¡"#, #"!"#)
        samples << word(punctuatedBy: #"""#)
        samples << word(punctuatedBy: #"'"#)
        samples << word(punctuatedBy: #"“"#, #"”"#)
        samples << word(punctuatedBy: #"‘"#, #"’"#)
        // Symbols
        samples << word(punctuatedBy: #"`"#)
        samples << word(punctuatedBy: #"!"#)
        samples << word(punctuatedBy: #"@"#)
        samples << word(punctuatedBy: #"#"#)
        samples << word(punctuatedBy: #"$"#)
        samples << word(punctuatedBy: #"%"#)
        samples << word(punctuatedBy: #"^"#)
        samples << word(punctuatedBy: #"&"#)
        samples << word(punctuatedBy: #"*"#)
        samples << word(punctuatedBy: #"-"#)
        samples << word(punctuatedBy: #"_"#)
        samples << word(punctuatedBy: #"="#)
        samples << word(punctuatedBy: #"+"#)
        samples << word(punctuatedBy: #"!"#)

        continueAfterFailure = true

        for (input, expectedOutput) in samples {
            let buf = try makeBuffer(input)
            let originalSelecton = buf.selectedRange

            XCTAssertNoThrow(
                buf.select(try buf.wordRange(for: originalSelecton)),
                "Given \"\(sanitized(input))\""
            )
            assertBufferState(
                buf, expectedOutput,
                "Given \"\(sanitized(input))\"")
        }
    }

    func testWordRange_InvalidInputRange() throws {
        let buffer = MutableStringBuffer("Lorem ipsum")
        let expectedAvailableRange = NSRange(location: 0, length: 11)

        let invalidRanges: [NSRange] = [
            .init(location: -1, length: 999),
            .init(location: -1, length: 1),
            .init(location: -1, length: 0),
            .init(location: 11, length: -2),
            .init(location: 11, length: -1),
            .init(location: 1, length: 999),
            .init(location: 11, length: 1),
            .init(location: 12, length: 0),
            .init(location: 100, length: 999),
        ]
        for invalidRange in invalidRanges {
            assertThrows(
                try buffer.wordRange(for: invalidRange),
                error: BufferAccessFailure.outOfRange(
                    requested: invalidRange,
                    available: expectedAvailableRange
                ),
                "Selecting word range in \(invalidRange)"
            )
        }
    }
}
