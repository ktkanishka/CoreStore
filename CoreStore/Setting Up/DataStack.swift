//
//  DataStack.swift
//  CoreStore
//
//  Copyright © 2014 John Rommel Estropia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import CoreData
#if USE_FRAMEWORKS
    import GCDKit
#endif


// TODO: move these to PersistentStore wrapper

#if os(tvOS)
    internal let systemDirectorySearchPath = NSSearchPathDirectory.CachesDirectory
#else
    internal let systemDirectorySearchPath = NSSearchPathDirectory.ApplicationSupportDirectory
#endif

internal let defaultSystemDirectory = NSFileManager.defaultManager().URLsForDirectory(
    systemDirectorySearchPath,
    inDomains: .UserDomainMask
).first!
internal let defaultRootDirectory = defaultSystemDirectory.URLByAppendingPathComponent(
    NSBundle.mainBundle().bundleIdentifier ?? "com.CoreStore.DataStack",
    isDirectory: true
)
internal let applicationName = (NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleName") as? String) ?? "CoreData"
internal let defaultSQLiteStoreFileURL = defaultRootDirectory
    .URLByAppendingPathComponent(applicationName, isDirectory: false)
    .URLByAppendingPathExtension("sqlite")


// MARK: - DataStack

/**
 The `DataStack` encapsulates the data model for the Core Data stack. Each `DataStack` can have multiple data stores, usually specified as a "Configuration" in the model editor. Behind the scenes, the DataStack manages its own `NSPersistentStoreCoordinator`, a root `NSManagedObjectContext` for disk saves, and a shared `NSManagedObjectContext` designed as a read-only model interface for `NSManagedObjects`.
 */
public final class DataStack {
    
    /**
     Initializes a `DataStack` from an `NSManagedObjectModel`.
     
     - parameter modelName: the name of the (.xcdatamodeld) model file. If not specified, the application name will be used.
     - parameter bundle: an optional bundle to load models from. If not specified, the main bundle will be used.
     - parameter migrationChain: the `MigrationChain` that indicates the sequence of model versions to be used as the order for progressive migrations. If not specified, will default to a non-migrating data stack.
     */
    public required init(modelName: String = applicationName, bundle: NSBundle = NSBundle.mainBundle(), migrationChain: MigrationChain = nil) {
        
        CoreStore.assert(
            migrationChain.valid,
            "Invalid migration chain passed to the \(typeName(DataStack)). Check that the model versions' order is correct and that no repetitions or ambiguities exist."
        )
        
        let model = NSManagedObjectModel.fromBundle(
            bundle,
            modelName: modelName,
            modelVersionHints: migrationChain.leafVersions
        )
        
        self.coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        self.rootSavingContext = NSManagedObjectContext.rootSavingContextForCoordinator(self.coordinator)
        self.mainContext = NSManagedObjectContext.mainContextForRootContext(self.rootSavingContext)
        self.model = model
        self.migrationChain = migrationChain
        
        self.rootSavingContext.parentStack = self
    }
    
    /**
     Returns the `DataStack`'s model version. The version string is the same as the name of the version-specific .xcdatamodeld file.
     */
    public var modelVersion: String {
        
        return self.model.currentModelVersion!
    }
    
    /**
     Returns the entity name-to-class type mapping from the `DataStack`'s model.
     */
    public var entityTypesByName: [String: NSManagedObject.Type] {
        
        return self.model.entityTypesMapping()
    }
    
    /**
     Returns the `NSEntityDescription` for the specified `NSManagedObject` subclass.
     */
    public func entityDescriptionForType(type: NSManagedObject.Type) -> NSEntityDescription? {
        
        return NSEntityDescription.entityForName(
            self.model.entityNameForClass(type),
            inManagedObjectContext: self.mainContext
        )
    }
    
    /**
     Returns the `NSManagedObjectID` for the specified object URI if it exists in the persistent store.
     */
    public func objectIDForURIRepresentation(url: NSURL) -> NSManagedObjectID? {
        
        return self.coordinator.managedObjectIDForURIRepresentation(url)
    }
    
    /**
     Creates a `Storage` of the specified store type with default values and adds it to the stack. This method blocks until completion.
     
     - parameter storeType: the `Storage` type
     - returns: the `Storage` added to the stack
     */
    public func addStoreAndWait<T: Storage where T: DefaultInitializableStore>(storeType: T.Type) throws -> T {
        
        return try self.addStoreAndWait(storeType.init())
    }
    
    /**
     Adds a `Storage` to the stack and blocks until completion.
     
     - parameter store: the `Storage`
     - returns: the `Storage` added to the stack
     */
    public func addStoreAndWait<T: Storage>(store: T) throws -> T {
        
        CoreStore.assert(
            store.internalStore == nil,
            "The specified store was already added to the data stack: \(store)"
        )
        
        do {
            
            let persistentStore = try store.addToPersistentStoreCoordinatorSynchronously(self.coordinator)
            self.updateMetadataForPersistentStore(persistentStore)
            store.internalStore = persistentStore
            return store
        }
        catch {
            
            CoreStore.handleError(
                error as NSError,
                "Failed to add \(typeName(T)) to the stack."
            )
            throw error
        }
    }
    
    /**
     Adds to the stack an SQLite store from the given SQLite file name.
     
     - parameter fileName: the local filename for the SQLite persistent store in the "Application Support/<bundle id>" directory (or the "Caches/<bundle id>" directory on tvOS). A new SQLite file will be created if it does not exist. Note that if you have multiple configurations, you will need to specify a different `fileName` explicitly for each of them.
     - parameter configuration: an optional configuration name from the model file. If not specified, defaults to `nil`, the "Default" configuration. Note that if you have multiple configurations, you will need to specify a different `fileName` explicitly for each of them.
     - parameter resetStoreOnModelMismatch: Set to true to delete the store on model mismatch; or set to false to throw exceptions on failure instead. Typically should only be set to true when debugging, or if the persistent store can be recreated easily. If not specified, defaults to false
     - returns: the `NSPersistentStore` added to the stack.
     */
    public func addSQLiteStoreAndWait(fileName fileName: String, configuration: String? = nil, resetStoreOnModelMismatch: Bool = false) throws -> NSPersistentStore {
        
        return try self.addSQLiteStoreAndWait(
            fileURL: defaultRootDirectory
                .URLByAppendingPathComponent(
                    fileName,
                    isDirectory: false
            ),
            configuration: configuration,
            resetStoreOnModelMismatch: resetStoreOnModelMismatch
        )
    }
    
    /**
     Adds to the stack an SQLite store from the given SQLite file URL.
     
     - parameter fileURL: the local file URL for the SQLite persistent store. A new SQLite file will be created if it does not exist. If not specified, defaults to a file URL pointing to a "<Application name>.sqlite" file in the "Application Support/<bundle id>" directory (or the "Caches/<bundle id>" directory on tvOS). Note that if you have multiple configurations, you will need to specify a different `fileURL` explicitly for each of them.
     - parameter configuration: an optional configuration name from the model file. If not specified, defaults to `nil`, the "Default" configuration. Note that if you have multiple configurations, you will need to specify a different `fileURL` explicitly for each of them.
     - parameter resetStoreOnModelMismatch: Set to true to delete the store on model mismatch; or set to false to throw exceptions on failure instead. Typically should only be set to true when debugging, or if the persistent store can be recreated easily. If not specified, defaults to false.
     - returns: the `NSPersistentStore` added to the stack.
     */
    public func addSQLiteStoreAndWait(fileURL fileURL: NSURL = defaultSQLiteStoreFileURL, configuration: String? = nil, resetStoreOnModelMismatch: Bool = false) throws -> NSPersistentStore {
        
        CoreStore.assert(
            fileURL.fileURL,
            "The specified file URL for the SQLite store is invalid: \"\(fileURL)\""
        )
        
        let coordinator = self.coordinator;
        if let store = coordinator.persistentStoreForURL(fileURL) {
            
            guard store.type == NSSQLiteStoreType
                && store.configurationName == (configuration ?? Into.defaultConfigurationName) else {
                    
                    let error = NSError(coreStoreErrorCode: .DifferentPersistentStoreExistsAtURL)
                    CoreStore.handleError(
                        error,
                        "Failed to add SQLite \(typeName(NSPersistentStore)) at \"\(fileURL)\" because a different \(typeName(NSPersistentStore)) at that URL already exists."
                    )
                    
                    throw error
            }
            
            return store
        }
        
        let fileManager = NSFileManager.defaultManager()
        _ = try? fileManager.createDirectoryAtURL(
            fileURL.URLByDeletingLastPathComponent!,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let options = self.optionsForSQLiteStore()
        do {
            
            let store = try coordinator.addPersistentStoreSynchronously(
                NSSQLiteStoreType,
                configuration: configuration,
                URL: fileURL,
                options: options
            )
            self.updateMetadataForPersistentStore(store)
            return store
        }
        catch let error as NSError where resetStoreOnModelMismatch && error.isCoreDataMigrationError {
            
            fileManager.removeSQLiteStoreAtURL(fileURL)
            
            do {
                
                let store = try coordinator.addPersistentStoreSynchronously(
                    NSSQLiteStoreType,
                    configuration: configuration,
                    URL: fileURL,
                    options: options
                )
                self.updateMetadataForPersistentStore(store)
                return store
            }
            catch {
                
                CoreStore.handleError(
                    error as NSError,
                    "Failed to add SQLite \(typeName(NSPersistentStore)) at \"\(fileURL)\"."
                )
                throw error
            }
        }
        catch {
            
            CoreStore.handleError(
                error as NSError,
                "Failed to add SQLite \(typeName(NSPersistentStore)) at \"\(fileURL)\"."
            )
            throw error
        }
    }
    
    
    // MARK: Internal
    
    internal let coordinator: NSPersistentStoreCoordinator
    internal let rootSavingContext: NSManagedObjectContext
    internal let mainContext: NSManagedObjectContext
    internal let model: NSManagedObjectModel
    internal let migrationChain: MigrationChain
    internal let childTransactionQueue: GCDQueue = .createSerial("com.coreStore.dataStack.childTransactionQueue")
    internal let migrationQueue: NSOperationQueue = {
        
        let migrationQueue = NSOperationQueue()
        migrationQueue.maxConcurrentOperationCount = 1
        migrationQueue.name = "com.coreStore.migrationOperationQueue"
        migrationQueue.qualityOfService = .Utility
        migrationQueue.underlyingQueue = dispatch_queue_create("com.coreStore.migrationQueue", DISPATCH_QUEUE_SERIAL)
        return migrationQueue
    }()
    
    internal func optionsForSQLiteStore() -> [String: AnyObject] {
        
        return [NSSQLitePragmasOption: ["journal_mode": "WAL"]]
    }
    
    internal func entityNameForEntityClass(entityClass: AnyClass) -> String? {
        
        return self.model.entityNameForClass(entityClass)
    }
    
    internal func persistentStoresForEntityClass(entityClass: AnyClass) -> [NSPersistentStore]? {
        
        var returnValue: [NSPersistentStore]? = nil
        self.storeMetadataUpdateQueue.barrierSync {
            
            returnValue = self.entityConfigurationsMapping[NSStringFromClass(entityClass)]?.map {
                
                return self.configurationStoreMapping[$0]!
            } ?? []
        }
        return returnValue
    }
    
    internal func persistentStoreForEntityClass(entityClass: AnyClass, configuration: String?, inferStoreIfPossible: Bool) -> (store: NSPersistentStore?, isAmbiguous: Bool) {
        
        var returnValue: (store: NSPersistentStore?, isAmbiguous: Bool) = (store: nil, isAmbiguous: false)
        self.storeMetadataUpdateQueue.barrierSync {
            
            let configurationsForEntity = self.entityConfigurationsMapping[NSStringFromClass(entityClass)] ?? []
            if let configuration = configuration {
                
                if configurationsForEntity.contains(configuration) {
                    
                    returnValue = (store: self.configurationStoreMapping[configuration], isAmbiguous: false)
                    return
                }
                else if !inferStoreIfPossible {
                    
                    return
                }
            }
            
            switch configurationsForEntity.count {
                
            case 0:
                return
                
            case 1 where inferStoreIfPossible:
                returnValue = (store: self.configurationStoreMapping[configurationsForEntity.first!], isAmbiguous: false)
                
            default:
                returnValue = (store: nil, isAmbiguous: true)
            }
        }
        return returnValue
    }
    
    internal func updateMetadataForPersistentStore(persistentStore: NSPersistentStore) {
        
        self.storeMetadataUpdateQueue.barrierAsync {
            
            let configurationName = persistentStore.configurationName
            self.configurationStoreMapping[configurationName] = persistentStore
            for entityDescription in (self.coordinator.managedObjectModel.entitiesForConfiguration(configurationName) ?? []) {
                
                let managedObjectClassName = entityDescription.managedObjectClassName
                CoreStore.assert(
                    NSClassFromString(managedObjectClassName) != nil,
                    "The class \(typeName(managedObjectClassName)) for the entity \(typeName(entityDescription.name)) does not exist. Check if the subclass type and module name are properly configured."
                )
                
                if self.entityConfigurationsMapping[managedObjectClassName] == nil {
                    
                    self.entityConfigurationsMapping[managedObjectClassName] = []
                }
                self.entityConfigurationsMapping[managedObjectClassName]?.insert(configurationName)
            }
        }
    }
    
    
    // MARK: Private
    
    private let storeMetadataUpdateQueue = GCDQueue.createConcurrent("com.coreStore.persistentStoreBarrierQueue")
    private var configurationStoreMapping = [String: NSPersistentStore]()
    private var entityConfigurationsMapping = [String: Set<String>]()
    
    deinit {
        
        let coordinator = self.coordinator
        coordinator.persistentStores.forEach { _ = try? coordinator.removePersistentStore($0) }
    }
    
    
    // MARK: Deprecated
    
    @available(*, deprecated=2.0.0, message="Use addStoreAndWait(_:configuration:) by passing an InMemoryStore instance")
    public func addInMemoryStoreAndWait(configuration configuration: String? = nil) throws -> NSPersistentStore {
        
        return try self.addStoreAndWait(InMemoryStore).internalStore!
    }
}
