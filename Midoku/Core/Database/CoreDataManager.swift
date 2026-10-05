//
//  CoreDataManager.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager: @unchecked Sendable {
    static let shared = CoreDataManager()

    // Keep the existing Midoku.sqlite and Local.sqlite store configurations so existing data survives.
    let container: NSPersistentContainer

    @MainActor
    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = Self.createContainer()
    }

    static func createContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Midoku")

        let storeDirectory = FileManager.default.applicationSupportDirectory

        let cloudDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Midoku.sqlite"))
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true

        // Earlier releases opened this same store with persistent history enabled.
        // Keep that option when disabling CloudKit mirroring: otherwise Core Data
        // can reopen an existing store read-only and every history/session save fails.
        // This tracks local transactions only; it does not enable iCloud sync.
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [
            cloudDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
                return
            }
            if let store = container.persistentStoreCoordinator.persistentStores.first(where: { $0.url == description.url }) {
                let name = description.url?.lastPathComponent ?? description.configuration ?? "database"
                if store.isReadOnly {
                    LogManager.logger.error("CoreDataManager: \(name) opened read-only; progress and session saves cannot succeed")
                } else {
                    LogManager.logger.info("CoreDataManager: \(name) opened writable")
                }
            }
        }

        return container
    }

    @MainActor
    func save() {
        do {
            try context.save()
        } catch {
            LogManager.logger.error("CoreDataManager.save: \(error.localizedDescription)")
        }
    }

//    func saveIfNeeded() {
//        if context.hasChanges {
//            save()
//        }
//    }

    func remove(_ objectID: NSManagedObjectID) {
        container.performBackgroundTask { context in
            let object = context.object(with: objectID)
            context.delete(object)
            try? context.save()
        }
    }

    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    func queueClear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let objects = (try? context.fetch(request)) ?? []
        for object in objects {
            context.delete(object)
        }
    }

    // TODO: clean this up
    func migrateChapterHistory(progress: (@Sendable (Float) -> Void)? = nil) async {
        LogManager.logger.info("Beginning chapter history migration for 0.6")

        await container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            let historyObjects = (try? context.fetch(request)) ?? []
            let total = Float(historyObjects.count)
            var i: Float = 0
            var count = 0
            for historyObject in historyObjects {
                progress?(i / total)
                i += 1
                guard
                    historyObject.chapter == nil,
                    let chapterObject = self.getChapter(
                        chapterId: historyObject.identifier,
                        context: context
                    )
                else { continue }
                historyObject.chapter = chapterObject
                count += 1
            }
            try? context.save()

            LogManager.logger.info("Migrated \(count)/\(historyObjects.count) history objects")
        }
    }
}
