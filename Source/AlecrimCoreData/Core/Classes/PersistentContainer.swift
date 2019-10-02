//
//  GenericPersistentContainer.swift
//  AlecrimCoreData
//
//  Created by Vanderlei Martinelli on 2016-06-20.
//  Copyright © 2016 Alecrim. All rights reserved.
//

import Foundation
import CoreData

// MARK: -

public struct PersistentContainerOptions {
    public static var defaultBatchSize: Int = 20
    public static var defaultComparisonPredicateOptions: NSComparisonPredicate.Options = [.caseInsensitive, .diacriticInsensitive]
}

open class PersistentContainer: GenericPersistentContainer<NSManagedObjectContext> {
    
}

// MARK: -

public protocol PersistentStoreDescription {
    var type: String { get set }
    var configuration: String? { get set }
    var url: URL? { get set }
    var options: [String : NSObject] { get }
    
    var isReadOnly: Bool { get set }
    var timeout: TimeInterval { get set }
    var sqlitePragmas: [String : NSObject] { get }
    
    var shouldAddStoreAsynchronously: Bool { get set }
    var shouldMigrateStoreAutomatically: Bool { get set }
    var shouldInferMappingModelAutomatically: Bool { get set }

    func setOption(_ option: NSObject?, forKey key: String)
    func setValue(_ value: NSObject?, forPragmaNamed name: String)
}

// MARK: -

internal protocol UnderlyingPersistentContainer: class {
    var name: String { get }
    var managedObjectModel: NSManagedObjectModel { get }
    var persistentStoreCoordinator: NSPersistentStoreCoordinator { get }
    
    var viewContext: NSManagedObjectContext { get }
    var alc_persistentStoreDescriptions: [PersistentStoreDescription] { get set }
    
    func alc_loadPersistentStores(completionHandler block: @escaping (PersistentStoreDescription, Error?) -> Void)
    func newBackgroundContext() -> NSManagedObjectContext
    
    func configureDefaults(for context: NSManagedObjectContext)
    
    init(name: String, managedObjectModel model: NSManagedObjectModel, contextType: NSManagedObjectContext.Type, directoryURL: URL)
}

// MARK: -

open class GenericPersistentContainer<ContextType: NSManagedObjectContext> {

    // MARK: -

    open class func directoryURL() -> URL {
        if #available(iOS 10.0, macOSApplicationExtension 10.12, iOSApplicationExtension 10.0, tvOSApplicationExtension 10.0, watchOSApplicationExtension 3.0, *) {
            return NativePersistentContainer.defaultDirectoryURL()
        }
        else {
            return CustomPersistentContainer.defaultDirectoryURL()
        }
    }

    // MARK: -

    private let underlyingPersistentContainer: UnderlyingPersistentContainer
    
    // MARK: -
    
    public var name: String { return self.underlyingPersistentContainer.name }
    
    public var viewContext: ContextType { return self.underlyingPersistentContainer.viewContext as! ContextType }
    
    public var managedObjectModel: NSManagedObjectModel { return self.underlyingPersistentContainer.managedObjectModel }
    
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator { return self.underlyingPersistentContainer.persistentStoreCoordinator }
    
    public var persistentStoreDescriptions: [PersistentStoreDescription] {
        get {
            return self.underlyingPersistentContainer.alc_persistentStoreDescriptions
        }
        set {
            self.underlyingPersistentContainer.alc_persistentStoreDescriptions = newValue
        }
    }
    
    // MARK: -

    @discardableResult
    public convenience init(name: String, completionHandler: @escaping ((GenericPersistentContainer<ContextType>) -> Void),
                            failure: ((Error) -> Void)? = nil) {
        self.init(name: name, automaticallyLoadPersistentStores: true, completionHandler: completionHandler, failure: failure)
    }

    public convenience init(name: String) {
        self.init(name: name, automaticallyLoadPersistentStores: true, completionHandler: { _ in
        }, failure: { error in
            AlecrimCoreDataError.handleError(error)
        })
    }
    
    public convenience init(name: String, automaticallyLoadPersistentStores: Bool,
                            completionHandler: @escaping ((GenericPersistentContainer<ContextType>) -> Void),
                            failure: ((Error) -> Void)?) {
        if let modelURL = Bundle.main.url(forResource: name, withExtension: "momd") ?? Bundle.main.url(forResource: name, withExtension: "mom") {
            if let model = NSManagedObjectModel(contentsOf: modelURL) {
                self.init(name: name, managedObjectModel: model, automaticallyLoadPersistentStores: automaticallyLoadPersistentStores,
                          completionHandler: completionHandler, failure: failure)
                return
            }
            
            fatalError("CoreData: Failed to load model at path: \(modelURL)")
        }
        
        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle.main]) else {
            fatalError("Couldn't find managed object model in main bundle.")
            
        }

        self.init(name: name, managedObjectModel: model, automaticallyLoadPersistentStores: automaticallyLoadPersistentStores,
                  completionHandler: completionHandler, failure: failure)
    }
    
    
    public init(name: String, managedObjectModel model: NSManagedObjectModel, automaticallyLoadPersistentStores: Bool,
                completionHandler: @escaping ((GenericPersistentContainer<ContextType>) -> Void), failure: ((Error) -> Void)?) {
        let directoryURL = type(of: self).directoryURL()
        
        do {
            try FileManager.default.createDirectory(atPath: directoryURL.path, withIntermediateDirectories: true, attributes: nil)
        } catch {
            AlecrimCoreDataError.handleError(error)
        }
        
        //
        if #available(iOS 10.0, macOSApplicationExtension 10.12, iOSApplicationExtension 10.0, tvOSApplicationExtension 10.0, watchOSApplicationExtension 3.0, *) {
            self.underlyingPersistentContainer = NativePersistentContainer(name: name, managedObjectModel: model, contextType: ContextType.self, directoryURL: directoryURL)
        }
        else {
            self.underlyingPersistentContainer = CustomPersistentContainer(name: name, managedObjectModel: model, contextType: ContextType.self, directoryURL: directoryURL)
        }
        
        //
        self.underlyingPersistentContainer.configureDefaults(for: self.viewContext)
        
        //
        if automaticallyLoadPersistentStores {
            self.loadPersistentStores { storeDescription, error in
                if let error = error {
                    failure?(error)
                } else {
                    completionHandler(self)
                }
            }
        } else {
            completionHandler(self)
        }
    }
    
    // MARK: -
    
    public func loadPersistentStores(completionHandler block: @escaping (PersistentStoreDescription, Error?) -> Void) {
        self.underlyingPersistentContainer.alc_loadPersistentStores(completionHandler: block)
    }
    
    public func newBackgroundContext() -> ContextType {
        let context = self.underlyingPersistentContainer.newBackgroundContext() as! ContextType
        self.underlyingPersistentContainer.configureDefaults(for: context)
        
        return context
    }
    
    public func performBackgroundTask(_ block: @escaping (ContextType) -> Void) {
        let context = self.newBackgroundContext()
        
        context.perform {
            block(context)
        }
    }
    
}

