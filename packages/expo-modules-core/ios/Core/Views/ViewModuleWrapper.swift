import ObjectiveC

/**
 A protocol that helps in identifying whether the instance of `ViewModuleWrapper` is of a dynamically created class.
 */
@objc
protocol DynamicModuleWrapperProtocol {
  @objc
  optional func wrappedModule() -> ViewModuleWrapper
}

/**
 Each module that has a view manager definition needs to be wrapped by `RCTViewManager`.
 Unfortunately, we can't use just one class because React Native checks for duplicated classes.
 We're generating its subclasses in runtime as a workaround.
 */
@objc
public final class ViewModuleWrapper: RCTViewManager, DynamicModuleWrapperProtocol {
  /**
   A reference to the module holder that stores the module definition.
   */
  weak var moduleHolder: ModuleHolder?
  /**
   A reference to the module definition
   */
  var viewDefinition: AnyViewDefinition?

  /**
   A boolean indicating if the view manager represents the default module view – the first exported definition available without specifying a view name.
   */
  var isDefaultModuleView: Bool = true

  /**
   The designated initializer. At first, we use this base class to hide `ModuleHolder` from Objective-C runtime.
   */
  public init(_ moduleHolder: ModuleHolder, _ viewDefinition: AnyViewDefinition, isDefaultModuleView: Bool = false) {
    self.moduleHolder = moduleHolder
    self.viewDefinition = viewDefinition
    self.isDefaultModuleView = isDefaultModuleView
  }

  /**
   The designated initializer that is used by React Native to create module instances.
   https://github.com/facebook/react-native/blob/540c41be9/packages/react-native/React/Views/RCTComponentData.m#L506-L507
   It doesn't matter to return dummy class here. The wrapper will then to subclass dynamically.
   Must be called on a dynamic class to get access to underlying wrapped module. Throws fatal exception otherwise.
   */
  @objc
  public override init() {
    super.init()
    guard let module = (self as DynamicModuleWrapperProtocol).wrappedModule?() else {
      return
    }
    self.moduleHolder = module.moduleHolder
    self.viewDefinition = moduleHolder?.definition.views[DEFAULT_MODULE_VIEW]
  }

  /**
   Dummy initializer, for use only in `EXModuleRegistryAdapter.extraModulesForModuleRegistry:`.
   */
  @objc
  public init(dummy: Any?) {
    super.init()
  }

  /**
   Returns the original name of the wrapped module.
   */
  @objc
  public func name() -> String {
    guard let moduleHolder, let viewDefinition else {
      fatalError("Failed to create ModuleHolder or a viewDefinition")
    }
    return self.isDefaultModuleView ? moduleHolder.name : "\(moduleHolder.name)_\(viewDefinition.name)"
  }

  /**
   Returns the original name of the wrapped module.
   */
  @objc
  public func moduleName() -> String {
    guard let moduleHolder else {
      fatalError("Failed to create ModuleHolder")
    }
    return moduleHolder.name
  }

  /**
   Returns the original name of the wrapped module.
   */
  @objc
  public func viewName() -> String {
    guard let moduleHolder, let viewDefinition else {
      fatalError("Failed to create ModuleHolder or a viewDefinition")
    }
    return self.isDefaultModuleView ? DEFAULT_MODULE_VIEW : viewDefinition.name
  }

  /**
   Static function that returns the class name, but keep in mind that dynamic wrappers
   have custom class name (see `objc_allocateClassPair` invocation in `createViewModuleWrapperClass`).
   */
  @objc
  public override class func moduleName() -> String {
    return NSStringFromClass(Self.self)
  }

  /**
   The view manager wrapper doesn't require main queue setup — it doesn't call any UI-related stuff on `init`.
   Also, lazy-loaded modules must return false here.
   */
  @objc
  public override class func requiresMainQueueSetup() -> Bool {
    return false
  }

  /**
   Creates a view from the wrapped module.
   */
  @objc
  public override func view() -> UIView! {
    guard let appContext = moduleHolder?.appContext else {
      fatalError(Exceptions.AppContextLost().reason)
    }
    guard let view = try? viewDefinition?.createView(appContext: appContext)?.toUIView() else {
      fatalError("Cannot create a view '\(String(describing: viewDefinition?.name))' from module '\(String(describing: self.name))'")
    }
    return view
  }

  public static let viewManagerAdapterPrefix = "ViewManagerAdapter_"

  /**
   Creates a subclass of `ViewModuleWrapper` in runtime. The new class overrides `moduleName` stub.
   */
  @objc
  public static func createViewModuleWrapperClass(module: ViewModuleWrapper, appId: String?) -> ViewModuleWrapper.Type? {
    // We're namespacing the view name so we know it uses our architecture.
    let prefixedViewName = if let appId = appId {
      "\(viewManagerAdapterPrefix)\(module.name())_\((appId))"
    } else {
      "\(viewManagerAdapterPrefix)\(module.name())"
    }

    return prefixedViewName.withCString { viewNamePtr in
      // Create a new class that inherits from `ViewModuleWrapper`. The class name passed here, doesn't work for Swift classes,
      // so we also have to override `moduleName` class method.
      let wrapperClass: AnyClass? = objc_allocateClassPair(ViewModuleWrapper.self, viewNamePtr, 0)

      // Dynamically add instance method returning wrapped module to the dynamic wrapper class.
      // React Native initializes modules with `init` without params,
      // so there is no other way to pass it to the instances.
      let wrappedModuleBlock: @convention(block) () -> ViewModuleWrapper = { module }
      let wrappedModuleImp: IMP = imp_implementationWithBlock(wrappedModuleBlock)
      class_addMethod(wrapperClass, #selector(DynamicModuleWrapperProtocol.wrappedModule), wrappedModuleImp, "@@:")

      return wrapperClass as? ViewModuleWrapper.Type
    }
  }
}

// The direct event implementation can be cached and lazy-loaded (global and static variables are lazy by default in Swift).
let directEventBlockImplementation = imp_implementationWithBlock({ ["RCTDirectEventBlock"] } as @convention(block) () -> [String])
