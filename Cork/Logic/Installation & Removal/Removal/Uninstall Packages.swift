//
//  Uninstall Packages.swift
//  Cork
//
//  Created by David Bureš on 05.02.2023.
//

import Foundation
import SwiftUI

@MainActor
func uninstallSelectedPackage(
    package: BrewPackage,
    brewData: BrewDataStorage,
    appState: AppState,
    outdatedPackageTracker: OutdatedPackageTracker,
    shouldRemoveAllAssociatedFiles: Bool,
    shouldApplyUninstallSpinnerToRelevantItemInSidebar: Bool = false
) async throws
{
    /// Store the old navigation selection to see if it got updated in the middle of switching
    let oldNavigationSelectionID: UUID? = appState.navigationSelection

    if shouldApplyUninstallSpinnerToRelevantItemInSidebar
    {
        if !package.isCask
        {
            brewData.installedFormulae = Set(brewData.installedFormulae.map
            { formula in
                var copyFormula = formula
                if copyFormula.name == package.name
                {
                    copyFormula.changeBeingModifiedStatus()
                }
                return copyFormula
            })
        }
        else
        {
            brewData.installedCasks = Set(brewData.installedCasks.map
            { cask in
                var copyCask = cask
                if copyCask.name == package.name
                {
                    copyCask.changeBeingModifiedStatus()
                }
                return copyCask
            })
        }
    }
    else
    {
        appState.isShowingUninstallationProgressView = true
    }

    print("Will try to remove package \(package.name)")
    var uninstallCommandOutput: TerminalOutput

    if !shouldRemoveAllAssociatedFiles
    {
        uninstallCommandOutput = await shell(AppConstants.brewExecutablePath, ["uninstall", package.name])
    }
    else
    {
        uninstallCommandOutput = await shell(AppConstants.brewExecutablePath, ["uninstall", "--zap", package.name])
    }

    print(uninstallCommandOutput.standardError)

    if uninstallCommandOutput.standardError.contains("because it is required by")
    {
        print("Could not uninstall this package because it's a dependency")

        /// If the uninstallation failed, change the status back to "not being modified"
        resetPackageState(package: package, brewData: brewData)

        do
        {
            let dependencyNameExtractionRegex: String = "(?<=required by ).*?(?=, which)"

            var dependencyName: String

            dependencyName = try String(regexMatch(from: uninstallCommandOutput.standardError, regex: dependencyNameExtractionRegex))

            appState.offendingDependencyProhibitingUninstallation = dependencyName
            appState.fatalAlertType = .uninstallationNotPossibleDueToDependency
            appState.isShowingFatalError = true

            print("Name of offending dependency: \(dependencyName)")
        }
        catch let regexError as NSError
        {
            print("Failed to extract dependency name from output: \(regexError)")
            throw RegexError.regexFunctionCouldNotMatchAnything
        }
    }
    else if uninstallCommandOutput.standardError.contains("sudo: a terminal is required to read the password")
    {
        #warning("TODO: So far, this only stops the package from being removed from the tracker. Implement a tutorial on how to uninstall the package")
        
        print("Could not uninstall this package because sudo is required")
        
        appState.packageTryingToBeUninstalledWithSudo = package
        appState.isShowingSudoRequiredForUninstallSheet = true
        
        resetPackageState(package: package, brewData: brewData)
    }
    else
    {
        print("Uninstalling can proceed")

        switch package.isCask
        {
        case false:
            withAnimation
            {
                brewData.removeFormulaFromTracker(withName: package.name)
            }

        case true:
            withAnimation
            {
                brewData.removeCaskFromTracker(withName: package.name)
            }
        }

        if appState.navigationSelection != nil
        {
            /// Switch to the status page only if the user didn't open another details window in the middle of the uninstall process
            if oldNavigationSelectionID == appState.navigationSelection
            {
                appState.navigationSelection = nil
            }
        }
    }

    appState.isShowingUninstallationProgressView = false

    print(uninstallCommandOutput)

    /// If the user removed a package that was outdated, remove it from the outdated package tracker
    Task
    {
        if let index = outdatedPackageTracker.outdatedPackages.firstIndex(where: { $0.package.name == package.name })
        {
            outdatedPackageTracker.outdatedPackages.remove(at: index)
        }
    }
}

@MainActor
private func resetPackageState(package: BrewPackage, brewData: BrewDataStorage)
{
    if !package.isCask
    {
        brewData.installedFormulae = Set(brewData.installedFormulae.map
                                         { formula in
            var copyFormula = formula
            if copyFormula.name == package.name, copyFormula.isBeingModified == true
            {
                copyFormula.changeBeingModifiedStatus()
            }
            return copyFormula
        })
    }
    else
    {
        brewData.installedCasks = Set(brewData.installedCasks.map
                                      { cask in
            var copyCask = cask
            if copyCask.name == package.name, copyCask.isBeingModified == true
            {
                copyCask.changeBeingModifiedStatus()
            }
            return copyCask
        })
    }
}
