//
//  PasswordTableEntryTest.swift
//  passKitTests
//
//  Created by Yishi Lin on 2020/2/23.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class PasswordTableEntryTest: XCTestCase {
    func testExample() {
        let nameWithCategoryList = [
            "github",
            "github.com",
            "www.github.com",
            "personal/github",
            "personal/github.com",
            "personal/www.github.com",
            "github/personal",
            "github.com/personal",
            "www.github.com/personal",
            "github (personal)",
        ]
        let searchTextList1 = [
            "github.com",
            "www.github.com",
        ]
        let searchTextList2 = [
            "xx.com",
            "www.xx.com",
        ]

        for nameWithCategory in nameWithCategoryList {
            for searchText in searchTextList1 {
                XCTAssertTrue(PasswordTableEntry.match(nameWithCategory: nameWithCategory, searchText: searchText))
            }
            for searchText in searchTextList2 {
                XCTAssertFalse(PasswordTableEntry.match(nameWithCategory: nameWithCategory, searchText: searchText))
            }
        }
    }
}

final class PasswordTableEntrySearchTest: CoreDataTestCase {
    private func entries(_ paths: [String]) -> [PasswordTableEntry] {
        let context = controller.viewContext()
        return paths.map { path in
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return PasswordTableEntry(PasswordEntity.insert(name: name, path: path, isDir: false, into: context))
        }
    }

    func testSearchNeedsEveryWord() {
        let found = entries(["www/github.gpg", "work/github.gpg", "a/b.gpg"]).ranked(by: "work git").map(\.title)
        XCTAssertEqual(found, ["github"])
    }

    func testSearchIgnoresCaseAndAccents() {
        XCTAssertEqual(entries(["café.gpg"]).ranked(by: "CAFE").map(\.title), ["café"])
    }

    func testSearchNoLongerMatchesShortWordsInTheQuery() {
        // Folder "a" used to match any search containing an a.
        XCTAssertTrue(entries(["a/b.gpg"]).ranked(by: "amazon").isEmpty)
    }

    func testSearchRanksNamesBeforeFolders() {
        let paths = ["github/personal.gpg", "work/my-github.gpg", "www/github.com.gpg", "www/github.gpg"]
        XCTAssertEqual(entries(paths).ranked(by: "github").map(\.title), ["github", "github.com", "my-github", "personal"])
    }
}
