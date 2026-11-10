//
//  PasswordEntity.swift
//  passKit
//
//  Created by Mingshen Sun on 11/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import CoreData
import DequeModule
import Foundation
import ObjectiveGit
import SwiftyUserDefaults

public final class PasswordEntity: NSManagedObject, Identifiable {
    /// Name of the password, i.e., filename without extension.
    @NSManaged public var name: String

    /// A Boolean value indicating whether the entity is a directory.
    @NSManaged public var isDir: Bool

    /// A Boolean value indicating whether the entity is synced with remote repository.
    @NSManaged public var isSynced: Bool

    /// The relative file path of the password or directory.
    @NSManaged public var path: String

    /// The thumbnail image of the password if there is a url entry in the password.
    @NSManaged public var image: Data?

    /// The parent password entity.
    @NSManaged public var parent: PasswordEntity?

    /// A set of child password entities.
    @NSManaged public var children: Set<PasswordEntity>

    /// Whether it, or for a folder anything in it, has changes that are not pushed yet.
    public var hasUnsyncedChanges: Bool {
        isDir ? children.contains(where: \.hasUnsyncedChanges) : !isSynced
    }

    @nonobjc
    public static func fetchRequest() -> NSFetchRequest<PasswordEntity> {
        NSFetchRequest<PasswordEntity>(entityName: "PasswordEntity")
    }

    /// A String value with password directory and name, i.e., path without extension.
    public var nameWithDir: String {
        (path as NSString).deletingPathExtension
    }

    public var dirText: String {
        getDirArray().joined(separator: " > ")
    }

    public func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(path)
    }

    public func getDirArray() -> [String] {
        var parentEntity = parent
        var passwordCategoryArray: [String] = []
        while let current = parentEntity {
            passwordCategoryArray.append(current.name)
            parentEntity = current.parent
        }
        passwordCategoryArray.reverse()
        return passwordCategoryArray
    }

    public static func fetchAll(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func fetchAllPassword(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isDir = false")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func totalNumber(in context: NSManagedObjectContext) -> Int {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isDir = false")
        return (try? context.count(for: request)) ?? 0
    }

    public static func fetchUnsynced(in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "isSynced = false")
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func fetch(by path: String, in context: NSManagedObjectContext) -> PasswordEntity? {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "path = %@", path)
        return try? context.fetch(request).first as? Self
    }

    public static func fetch(by path: String, isDir: Bool, in context: NSManagedObjectContext) -> PasswordEntity? {
        let request = Self.fetchRequest()

        request.predicate = NSPredicate(format: "path = %@ and isDir = %@", path, isDir as NSNumber)
        return try? context.fetch(request).first as? Self
    }

    public static func fetch(by parent: PasswordEntity?, in context: NSManagedObjectContext) -> [PasswordEntity] {
        let request = Self.fetchRequest()
        request.predicate = NSPredicate(format: "parent = %@", parent ?? 0)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? context.fetch(request) as? [Self]) ?? []
    }

    public static func updateAllToSynced(in context: NSManagedObjectContext) -> Int {
        let request = NSBatchUpdateRequest(entity: Self.entity())
        request.resultType = .updatedObjectsCountResultType
        request.predicate = NSPredicate(format: "isSynced = false")
        request.propertiesToUpdate = ["isSynced": true]
        request.resultType = .updatedObjectIDsResultType
        let ids = (try? context.execute(request) as? NSBatchUpdateResult)?.result as? [NSManagedObjectID] ?? []
        mergeBatchChanges([NSUpdatedObjectsKey: ids], into: context)
        return ids.count
    }

    /// Batch requests skip the context, which keeps serving the objects as they were; saving changes to one
    /// that is gone from the store fails.
    private static func mergeBatchChanges(_ changes: [String: [NSManagedObjectID]], into context: NSManagedObjectContext) {
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
    }

    public static func deleteRecursively(entity: PasswordEntity, in context: NSManagedObjectContext) {
        var currentEntity: PasswordEntity? = entity

        while let node = currentEntity, node.children.isEmpty {
            let parent = node.parent
            context.delete(node)
            try? context.save()
            currentEntity = parent
        }
    }

    public static func deleteAll(in context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: Self.fetchRequest())
        deleteRequest.resultType = .resultTypeObjectIDs
        let ids = (try? context.execute(deleteRequest) as? NSBatchDeleteResult)?.result as? [NSManagedObjectID] ?? []
        mergeBatchChanges([NSDeletedObjectsKey: ids], into: context)
    }

    public static func exists(password: Password, in context: NSManagedObjectContext) -> Bool {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "name = %@ and path = %@ and isDir = false", password.name, password.path)
        if let count = try? context.count(for: request) {
            return count > 0
        }
        return false
    }

    @discardableResult
    public static func insert(name: String, path: String, isDir: Bool, into context: NSManagedObjectContext) -> PasswordEntity {
        let entity = PasswordEntity(context: context)
        entity.name = name
        entity.path = path
        entity.isDir = isDir
        entity.isSynced = false
        return entity
    }

    /// Brings the entities in line with the passwords under `url`. Those of files still there stay the same objects,
    /// so whatever holds one keeps a valid entity across a sync; the others are inserted or deleted.
    public static func initPasswordEntityCoreData(url: URL, in context: NSManagedObjectContext) {
        let localFileManager = FileManager.default
        let url = url.resolvingSymlinksInPath()

        let grouped = Dictionary(grouping: fetchAll(in: context)) { "\($0.isDir)\($0.path)" }
        grouped.values.flatMap { $0.dropFirst() }.forEach(context.delete)
        var existing = grouped.compactMapValues(\.first)

        // Directories are enumerated through their resolved URL, so that symbolically linked
        // directories are traversed as well. A link pointing back up the tree would make the
        // traversal loop forever, hence every directory also carries the resolved paths of
        // itself and all its ancestors.
        var queue: Deque = [Directory(entity: nil, path: "", url: url, ancestors: [url.path])]
        while let directory = queue.popFirst() {
            let (current, currentPath, currentURL, ancestors) = (directory.entity, directory.path, directory.url, directory.ancestors)
            let resourceKeys = Set<URLResourceKey>([.nameKey, .isDirectoryKey])
            let options = FileManager.DirectoryEnumerationOptions([.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            guard let directoryEnumerator = localFileManager.enumerator(at: currentURL, includingPropertiesForKeys: Array(resourceKeys), options: options) else {
                continue
            }
            for case let fileURL as URL in directoryEnumerator {
                // Keep the name and the path of the link itself, since pass uses symbolic
                // links to share one password between several entries. Only the type comes
                // from the target, because isDirectoryKey does not follow links.
                let resolvedURL = fileURL.resolvingSymlinksInPath()
                guard let name = (try? fileURL.resourceValues(forKeys: resourceKeys))?.name else {
                    continue
                }
                let isDirectory = (try? resolvedURL.resourceValues(forKeys: resourceKeys))?.isDirectory ?? false
                // Ignore files that are not passwords, e.g., a README.md documenting the store.
                guard isDirectory || (name as NSString).pathExtension.lowercased() == "gpg" else {
                    continue
                }
                let path = currentPath.isEmpty ? name : "\(currentPath)/\(name)"
                let passwordEntity = existing.removeValue(forKey: "\(isDirectory)\(path)") ?? {
                    let entity = PasswordEntity(context: context)
                    entity.isDir = isDirectory
                    entity.path = path
                    return entity
                }()
                let entityName = isDirectory ? name : (name as NSString).deletingPathExtension
                if passwordEntity.name != entityName {
                    passwordEntity.name = entityName
                }
                if passwordEntity.parent != current {
                    passwordEntity.parent = current
                }
                if isDirectory, !ancestors.contains(resolvedURL.path) {
                    queue.append(Directory(entity: passwordEntity, path: path, url: resolvedURL, ancestors: ancestors.union([resolvedURL.path])))
                }
            }
        }
        existing.values.forEach(context.delete)
    }
}

public extension PasswordEntity {
    @objc(addChildrenObject:)
    @NSManaged
    func addToChildren(_ value: PasswordEntity)

    @objc(removeChildrenObject:)
    @NSManaged
    func removeFromChildren(_ value: PasswordEntity)

    @objc(addChildren:)
    @NSManaged
    func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged
    func removeFromChildren(_ values: NSSet)
}

/// A directory still to be enumerated, with the resolved paths of itself and its ancestors.
private struct Directory {
    let entity: PasswordEntity?
    let path: String
    let url: URL
    let ancestors: Set<String>
}
