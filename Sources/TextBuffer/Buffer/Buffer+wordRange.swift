//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation

@usableFromInline
let wordBoundary: CharacterSet = .whitespacesAndNewlines
    .union(.punctuationCharacters)
    .union(.symbols)
    .union(.illegalCharacters)  // Not tested

extension CharacterSet {
    @usableFromInline
    static let nonWhitespaceOrNewlines: CharacterSet = .whitespacesAndNewlines.inverted
}

@usableFromInline
func computeWordRange(
    for baseRange: NSRange,
    in nsContent: NSString,
    contentRange: NSRange
) -> NSRange {
    func expanding(
        range searchRange: NSRange,
        upToCharactersFrom characterSet: CharacterSet
    ) -> NSRange {
        var expandedRange = searchRange
        expandedRange = expanding(range: expandedRange, upToCharactersFrom: characterSet, direction: .upstream)
        expandedRange = expanding(range: expandedRange, upToCharactersFrom: characterSet, direction: .downstream)
        return expandedRange
    }

    func expanding(
        range searchRange: NSRange,
        upToCharactersFrom characterSet: CharacterSet,
        direction: StringTraversalDirection
    ) -> NSRange {
        switch direction {
        case .upstream:
            let matchedLocation = nsContent.locationUpToCharacter(
                from: characterSet,
                direction: .upstream,
                in: contentRange.prefix(upTo: searchRange)
            )
            return NSRange(
                startLocation: matchedLocation ?? contentRange.location,
                endLocation: searchRange.endLocation
            )
        case .downstream:
            let matchedLocation = nsContent.locationUpToCharacter(
                from: characterSet,
                direction: .downstream,
                in: contentRange.suffix(after: searchRange)
            )
            return NSRange(
                startLocation: searchRange.location,
                endLocation: matchedLocation ?? contentRange.endLocation
            )
        }
    }

    func trimmingWhitespace(range: NSRange) -> NSRange {
        var result = range

        if let newEndLocation = nsContent.locationUpToCharacter(
            from: .nonWhitespaceOrNewlines,
            direction: .upstream,
            in: result.expanded(to: contentRange, direction: .upstream))
        {
            result = NSRange(
                startLocation: result.location,
                endLocation: max(newEndLocation, result.location)
            )
        }

        if let newStartLocation = nsContent.locationUpToCharacter(
            from: .nonWhitespaceOrNewlines,
            direction: .downstream,
            in: result.expanded(to: contentRange, direction: .downstream))
        {
            result = NSRange(
                startLocation: min(newStartLocation, result.endLocation),
                endLocation: result.endLocation
            )
        }

        return result
    }

    func nonWhitespaceLocation(closestTo location: Int) -> Int? {
        let downstreamNonWhitespaceLocation = nsContent.locationUpToCharacter(from: .nonWhitespaceOrNewlines, direction: .downstream, in: contentRange.suffix(after: location))
        let upstreamNonWhitespaceLocation = nsContent.locationUpToCharacter(from: .nonWhitespaceOrNewlines, direction: .upstream, in: contentRange.prefix(upTo: location))

        if let upstreamNonWhitespaceLocation,
           let downstreamNonWhitespaceLocation,
           (upstreamNonWhitespaceLocation ..< location).count == 0,
           downstreamNonWhitespaceLocation > location {
            return upstreamNonWhitespaceLocation
        }

        return downstreamNonWhitespaceLocation ?? upstreamNonWhitespaceLocation
    }

    var resultRange = expanding(
        range: trimmingWhitespace(range: baseRange),
        upToCharactersFrom: wordBoundary
    )

    if resultRange.length == 0,
       let closestNonWhitespaceLocation = nonWhitespaceLocation(closestTo: resultRange.location) {
        resultRange = expanding(range: .init(location: closestNonWhitespaceLocation, length: 0), upToCharactersFrom: .whitespacesAndNewlines)
    }

    if resultRange.length == 0, resultRange != baseRange {
        return baseRange
    }

    return resultRange
}

extension Buffer where Range == NSRange {
    /// Default word range computation for UTF-16-indexed buffers.
    ///
    /// Uses Foundation's character classification for word boundary detection.
    /// Only available when `Range == NSRange`.
    @inlinable
    public func wordRange(
        for baseRange: Range
    ) throws(BufferAccessFailure) -> Range {
        guard self.contains(range: baseRange)
        else { throw BufferAccessFailure.outOfRange(requested: baseRange, available: self.range) }

        return computeWordRange(
            for: baseRange,
            in: (self.content as NSString),
            contentRange: self.range
        )
    }
}

extension AsyncBuffer where Range == NSRange {
    @inlinable
    public func wordRange(
        for baseRange: Range
    ) async throws(BufferAccessFailure) -> Range {
        guard await self.contains(range: baseRange)
        else { throw BufferAccessFailure.outOfRange(requested: baseRange, available: await self.getRange()) }

        return computeWordRange(
            for: baseRange,
            in: (await self.getContent() as NSString),
            contentRange: await self.getRange()
        )
    }
}
