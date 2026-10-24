import CoreGraphics
import Foundation

public struct OCRTextLine: Equatable, Sendable {
    public let text: String
    /// Vision's normalized coordinates have their origin at the bottom left.
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public enum OCRTextOrdering {
    public static func text(from observations: [OCRTextLine], singleLine: Bool = false) -> String {
        let lines = observations.compactMap { observation -> OCRTextLine? in
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRTextLine(text: text, boundingBox: observation.boundingBox)
        }.sorted {
            if $0.boundingBox.midY != $1.boundingBox.midY { return $0.boundingBox.midY > $1.boundingBox.midY }
            if $0.boundingBox.minX != $1.boundingBox.minX { return $0.boundingBox.minX < $1.boundingBox.minX }
            return $0.text < $1.text
        }

        // Keep an anchor per row rather than a tolerance-based sort comparator;
        // a comparator with pairwise tolerances would not be transitive.
        var rows: [[OCRTextLine]] = []
        for line in lines {
            if let index = rows.firstIndex(where: { row in
                let anchor = row[0].boundingBox
                let tolerance = min(anchor.height, line.boundingBox.height) / 2
                return abs(anchor.midY - line.boundingBox.midY) <= tolerance
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        let text = rows.map { row in
            row.sorted {
                if $0.boundingBox.minX != $1.boundingBox.minX { return $0.boundingBox.minX < $1.boundingBox.minX }
                return $0.text < $1.text
            }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
        return singleLine ? self.singleLine(text) : text
    }

    public static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
