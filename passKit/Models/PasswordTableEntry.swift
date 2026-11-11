//
//  PasswordTableEntry.swift
//  passKit
//
//  Created by Yishi Lin on 2020/2/23.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import Foundation

public class PasswordTableEntry: NSObject {
    public let passwordEntity: PasswordEntity
    @objc public let title: String
    public let isDir: Bool
    public let isSynced: Bool
    public let categoryText: String

    public init(_ entity: PasswordEntity) {
        self.passwordEntity = entity
        self.title = entity.name
        self.isDir = entity.isDir
        self.isSynced = !entity.hasUnsyncedChanges
        self.categoryText = entity.dirText
    }

    /// Whether every word typed is in the entry's name or folders.
    public func matches(_ searchText: String) -> Bool {
        rank(for: searchText) != nil
    }

    /// Where the entry goes among the results of a search, lower first, or nil when it does not match: names that
    /// are the search, then names that start with it, then names that contain it, then matches in folders only.
    public func rank(for searchText: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let words = searchText.split(whereSeparator: \.isWhitespace)
        guard words.allSatisfy({ passwordEntity.nameWithDir.range(of: $0, options: options) != nil }) else {
            return nil
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if title.compare(query, options: options) == .orderedSame {
            return 0
        }
        if title.range(of: query, options: options.union(.anchored)) != nil {
            return 1
        }
        return title.range(of: query, options: options) != nil ? 2 : 3
    }

    /// Whether the entry is likely for a site, looser than a search, as a host like `www.github.com` should find
    /// an entry named `github`.
    public func matchesSite(_ host: String) -> Bool {
        Self.match(nameWithCategory: passwordEntity.nameWithDir, searchText: host)
    }

    public static func match(nameWithCategory: String, searchText: String) -> Bool {
        let titleSplit = nameWithCategory.split { !($0.isLetter || $0.isNumber || $0 == ".") }
        for str in titleSplit {
            if str.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            if searchText.localizedCaseInsensitiveContains(str) {
                return true
            }
        }

        return false
    }
}

public extension Sequence<PasswordTableEntry> {
    /// The entries that match a search, best first, or all of them by name when there is no search.
    func ranked(by searchText: String) -> [PasswordTableEntry] {
        let ranked: [(entry: PasswordTableEntry, rank: Int)] = compactMap { entry in
            guard !searchText.isEmpty else {
                return (entry, 0)
            }
            return entry.rank(for: searchText).map { (entry, $0) }
        }
        return ranked
            .sorted { lhs, rhs in
                guard lhs.rank == rhs.rank else {
                    return lhs.rank < rhs.rank
                }
                return lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
            }
            .map(\.entry)
    }
}
