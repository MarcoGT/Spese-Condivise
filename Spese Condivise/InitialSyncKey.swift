//
//  InitialSyncKey.swift
//  Spese Condivise
//
//  Created by Marco on 24.01.26.
//


import SwiftUI

private struct InitialSyncKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var initialSyncCompleted: Bool {
        get { self[InitialSyncKey.self] }
        set { self[InitialSyncKey.self] = newValue }
    }
}
