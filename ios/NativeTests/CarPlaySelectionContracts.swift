/// Headless checks for the installation lifecycle; no app or CarPlay scene is launched.
@main
enum CarPlaySelectionContracts {
  static func main() {
    verify("Server selection waits for installation") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let generation = controller.beginInstallation(preferredScope: .server)

      precondition(selections.isEmpty)
      precondition(controller.completeInstallation(generation: generation, succeeded: true))
      precondition(selections == [.server])
    }

    verify("late restoration replaces the pending default") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let generation = controller.beginInstallation(preferredScope: .local)
      controller.select(.server)

      precondition(selections.isEmpty)
      precondition(controller.completeInstallation(generation: generation, succeeded: true))
      precondition(selections == [.server])
    }

    verify("the latest in-flight source wins") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let generation = controller.beginInstallation(preferredScope: .server)
      controller.select(.local)
      controller.select(.server)

      precondition(selections.isEmpty)
      precondition(controller.completeInstallation(generation: generation, succeeded: true))
      precondition(selections == [.server])
    }

    verify("a stale root completion cannot select the replacement root") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let old = controller.beginInstallation(preferredScope: .server)
      let current = controller.beginInstallation(preferredScope: .local)

      precondition(!controller.completeInstallation(generation: old, succeeded: true))
      precondition(selections.isEmpty)
      precondition(controller.completeInstallation(generation: current, succeeded: true))
      precondition(selections == [.local])
    }

    verify("disconnect invalidates pending selection before reconnect") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let old = controller.beginInstallation(preferredScope: .server)
      controller.invalidate()

      precondition(!controller.completeInstallation(generation: old, succeeded: true))
      precondition(selections.isEmpty)
      let current = controller.beginInstallation(preferredScope: .server)
      precondition(controller.completeInstallation(generation: current, succeeded: true))
      precondition(selections == [.server])
    }

    verify("failed installation cannot apply selection before a successful retry") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let failed = controller.beginInstallation(preferredScope: .server)

      precondition(!controller.completeInstallation(generation: failed, succeeded: false))
      controller.select(.local)
      precondition(selections.isEmpty)
      let retry = controller.beginInstallation(preferredScope: .server)
      precondition(controller.completeInstallation(generation: retry, succeeded: true))
      precondition(selections == [.server])
    }

    verify("installed roots apply later source changes immediately") {
      var selections: [CarPlayScope] = []
      let controller = CarPlayRootSelectionController { selections.append($0) }
      let generation = controller.beginInstallation()

      precondition(controller.completeInstallation(generation: generation, succeeded: true))
      precondition(selections.isEmpty)
      controller.select(.server)
      controller.select(.local)
      precondition(selections == [.server, .local])
    }
  }

  private static func verify(_ name: String, run: () -> Void) {
    run()
    print("PASS: \(name)")
  }
}
