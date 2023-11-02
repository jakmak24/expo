//  Copyright © 2019 650 Industries. All rights reserved.

import ExpoModulesCore

public class DisabledAppController : IAppController {
  public private(set) var isStarted: Bool = false // this is always false for disabled controllers

  public weak var bridge: AnyObject?

  public weak var delegate: AppControllerDelegate?

  internal private(set) var isEmergencyLaunch: Bool = false
  private let initializationError: Error?
  private var launcher: AppLauncher?

  required init(error: Error?) {
    self.initializationError = error
    self.isEmergencyLaunch = error != nil
  }

  public func start() {
    let launcherNoDatabase = AppLauncherNoDatabase()
    launcher = launcherNoDatabase
    launcherNoDatabase.launchUpdate()

    delegate.let { _ in
      DispatchQueue.main.async { [weak self] in
        if let strongSelf = self {
          strongSelf.delegate?.appController(strongSelf, didStartWithSuccess: strongSelf.launchAssetUrl() != nil)
        }
      }
    }

    if let initializationError = self.initializationError {
      ErrorRecovery.writeErrorOrExceptionToLog(initializationError)
    }
  }

  private func launchedUpdate() -> Update? {
    return launcher?.launchedUpdate
  }

  public func launchAssetUrl() -> URL? {
    return launcher?.launchAssetUrl
  }

  public func getConstantsForModule() -> UpdatesModuleConstants {
    return UpdatesModuleConstants(
      launchedUpdate: launchedUpdate(),
      embeddedUpdate: nil,
      isEmergencyLaunch: self.isEmergencyLaunch,
      isEnabled: false,
      releaseChannel: "default", // TODO(wschurman),
      isUsingEmbeddedAssets: launcher?.isUsingEmbeddedAssets() ?? false,
      runtimeVersion: nil,
      checkOnLaunch: CheckAutomaticallyConfig.Never,
      requestHeaders: [:],
      assetFilesMap: launcher?.assetFilesMap
    )
  }

  public func requestRelaunch(success successBlockArg: @escaping () -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }

  public func checkForUpdate(success successBlockArg: @escaping (RemoteCheckResult) -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }

  public func fetchUpdate(success successBlockArg: @escaping (FetchUpdateResult) -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }

  public func getExtraParams(success successBlockArg: @escaping ([String : String]?) -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }

  public func setExtraParam(key: String, value: String?, success successBlockArg: @escaping () -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }

  public func getNativeStateMachineContext(success successBlockArg: @escaping (UpdatesStateContext) -> Void, error errorBlockArg: @escaping (ExpoModulesCore.Exception) -> Void) {
    errorBlockArg(UpdatesDisabledException())
  }
}
