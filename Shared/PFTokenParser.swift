//
//  PFTokenParser.swift
//  VPNGuard
//
//  Pure parser for `pfctl` console output. Kept in Shared so it can be
//  unit-tested without invoking pfctl.
//

import Foundation

enum PFTokenParser {

    /// Extracts the reference token from `pfctl -E` output, which looks like:
    ///
    ///     pf enabled
    ///     token : 1680000000
    ///
    /// The token is needed later to release the reference via `pfctl -X`.
    /// Returns nil when no token is present.
    static func parseReferenceToken(from output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            guard let range = line.range(of: "token") else { continue }
            let value = line[range.upperBound...]
                .drop(while: { $0 == " " || $0 == ":" || $0 == "\t" })
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
