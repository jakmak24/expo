//  Copyright © 2019 650 Industries. All rights reserved.

// swiftlint:disable line_length
// swiftlint:disable type_body_length
// swiftlint:disable closure_body_length

// this class used a bunch of implicit non-null patterns for member variables. not worth refactoring to appease lint.
// swiftlint:disable force_unwrapping

import Foundation
import ExpoModulesCore

public struct UpdatesModuleConstants {
  let launchedUpdate: Update?
  let embeddedUpdate: Update?
  let isEmergencyLaunch: Bool
  let isEnabled: Bool
  let releaseChannel: String
  let isUsingEmbeddedAssets: Bool
  let runtimeVersion: String?
  let checkOnLaunch: CheckAutomaticallyConfig
  let requestHeaders: [String: String]
  let assetFilesMap: [String: Any]?
}

public typealias AppRelaunchCompletionBlock = (_ error: Error?) -> Void

public enum FetchUpdateResult {
  case success(manifest: [String: Any])
  case failure
  case rollBackToEmbedded
  case error(error: Error)
}

@objc(EXUpdatesAppController)
public protocol IPublicAppController {
  /**
   The RCTBridge for which EXUpdates is providing the JS bundle and assets.
   This is optional, but required in order for `Updates.reload()` and Updates module events to work.
   */
  @objc weak var bridge: AnyObject? { get set }

  /**
   Delegate which will be notified when EXUpdates has an update ready to launch and
   `launchAssetUrl` is nonnull.
   */
  @objc weak var delegate: AppControllerDelegate? { get set }

  /**
   The URL on disk to source asset for the RCTBridge.
   Will be null until the AppController delegate method is called.
   This should be provided in the `sourceURLForBridge:` method of RCTBridgeDelegate.
   */
  @objc func launchAssetUrl() -> URL?

  @objc var isStarted: Bool { get }
  @objc func start()
}

public protocol IAppController : IPublicAppController {
  func getConstantsForModule() -> UpdatesModuleConstants
  func requestRelaunch(
    success successBlockArg: @escaping () -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
  func checkForUpdate(
    success successBlockArg: @escaping (_ remoteCheckResult: RemoteCheckResult) -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
  func fetchUpdate(
    success successBlockArg: @escaping (_ fetchUpdateResult: FetchUpdateResult) -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
  func getExtraParams(
    success successBlockArg: @escaping (_ extraParams: [String: String]?) -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
  func setExtraParam(
    key: String,
    value: String?,
    success successBlockArg: @escaping () -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
  func getNativeStateMachineContext(
    success successBlockArg: @escaping (_ stateMachineContext: UpdatesStateContext) -> Void,
    error errorBlockArg: @escaping (_ error: Exception) -> Void
  )
}

@objc(EXUpdatesAppControllerDelegate)
public protocol AppControllerDelegate: AnyObject {
  func appController(_ appController: IPublicAppController, didStartWithSuccess success: Bool)
}

/**
 * Main entry point to expo-updates in normal release builds (development clients, including Expo
 * Go, use a different entry point). Singleton that keeps track of updates state, holds references
 * to instances of other updates classes, and is the central hub for all updates-related tasks.
 *
 * The `start` method in this class should be invoked early in the application lifecycle, via
 * ExpoUpdatesReactDelegateHandler. It delegates to an instance of AppLoaderTask to start
 * the process of loading and launching an update, then responds appropriately depending on the
 * callbacks that are invoked.
 *
 * This class also provides getter methods to access information about the updates state, which are
 * used by the exported UpdatesModule through EXUpdatesService. Such information includes
 * references to: the database, the UpdatesConfig object, the path on disk to the updates
 * directory, any currently active AppLoaderTask, the current SelectionPolicy, the
 * error recovery handler, and the current launched update. This class is intended to be the source
 * of truth for these objects, so other classes shouldn't retain any of them indefinitely.
 */
@objc(EXUpdatesAppController)
@objcMembers
public class AppController: NSObject {
  private static var _sharedInstance: IAppController? = nil
  public static var sharedInstance: IAppController {
    get {
      assert(_sharedInstance != nil, "AppController.sharedInstace was called before the module was initialized")
      return _sharedInstance!
    }
  }

  public static func initializeWithoutStarting(configuration: [String: Any]?) {
    if _sharedInstance != nil {
      return
    }

    if UpdatesConfig.canCreateValidConfiguration(mergingOtherDictionary: configuration) {
      var config: UpdatesConfig?
      do {
        config = try UpdatesConfig.configWithExpoPlist(mergingOtherDictionary: configuration)
      } catch {
        NSException(
          name: .internalInconsistencyException,
          reason: "Cannot load configuration from Expo.plist. Please ensure you've followed the setup and installation instructions for expo-updates to create Expo.plist and add it to your Xcode project."
        )
        .raise()
      }

      let updatesDatabase = UpdatesDatabase()
      do {
        let directory = try initializeUpdatesDirectory()
        try initializeUpdatesDatabase(updatesDatabase: updatesDatabase, inUpdatesDirectory: directory)
        _sharedInstance = EnabledAppController(config: config!, database: updatesDatabase, updatesDirectory: directory)
      } catch {
        _sharedInstance = DisabledAppController(error: error)
        return
      }
    } else {
      _sharedInstance = DisabledAppController(error: nil) // TODO(wschurman): figure out config
    }
  }

  public static func initializeAsDevLauncherWithoutStarting() -> DevLauncherAppController {
    assert(_sharedInstance == nil, "UpdatesController must not be initialized prior to calling initializeAsDevLauncherWithoutStarting")

    var config: UpdatesConfig? = nil
    if UpdatesConfig.canCreateValidConfiguration(mergingOtherDictionary: nil) {
      config = try? UpdatesConfig.configWithExpoPlist(mergingOtherDictionary: nil)
    }

    var updatesDirectory: URL? = nil
    let updatesDatabase = UpdatesDatabase()
    var directoryDatabaseException: Error? = nil
    do {
      updatesDirectory = try initializeUpdatesDirectory()
      try initializeUpdatesDatabase(updatesDatabase: updatesDatabase, inUpdatesDirectory: updatesDirectory!)
    } catch {
      directoryDatabaseException = error
    }

    let appController = DevLauncherAppController(
      initialUpdatesConfiguration: config,
      updatesDirectory: updatesDirectory,
      updatesDatabase: updatesDatabase,
      directoryDatabaseException: directoryDatabaseException
    )
    _sharedInstance = appController
    return appController
  }

  private static func initializeUpdatesDirectory() throws -> URL {
    return try UpdatesUtils.initializeUpdatesDirectory()
  }

  private static func initializeUpdatesDatabase(updatesDatabase: UpdatesDatabase, inUpdatesDirectory updatesDirectory: URL) throws {
    var dbError: Error?
    let semaphore = DispatchSemaphore(value: 0)
    updatesDatabase.databaseQueue.async {
      do {
        try updatesDatabase.openDatabase(inDirectory: updatesDirectory)
      } catch {
        dbError = error
      }
      semaphore.signal()
    }

    _ = semaphore.wait(timeout: .distantFuture)

    if let dbError = dbError {
      throw dbError
    }
  }
}



// swiftlint:enable force_unwrapping
// swiftlint:enable closure_body_length
// swiftlint:enable line_length
// swiftlint:enable type_body_length
