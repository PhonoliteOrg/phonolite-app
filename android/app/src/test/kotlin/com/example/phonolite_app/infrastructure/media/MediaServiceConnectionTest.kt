package com.example.phonolite_app.infrastructure.media

// Dependency-free JVM checks: no Android service, notification, Flutter engine or worker.
object MediaServiceConnectionTest {
  @JvmStatic
  fun main(args: Array<String>) {
    aBoundServiceRequestsStartedOwnershipOnce()
    aPendingStartSurvivesAttachment()
    anAlreadyStartedServiceNeedsNoStartRequest()
    clearStopsAndAllowsANewStart()
    aLateStartAcknowledgementCannotUndoClear()
    detachResetsTheCurrentService()
    aReplacedObserverCannotResetTheCurrentService()
    aStaleStartedCallbackCannotMarkTheReplacement()
    aFailedStartCanBeRetried()
    sourceChangesOnlyNotifyTheCurrentObserver()

    println("MediaServiceConnection: 10 headless JVM checks passed")
  }

  private fun aBoundServiceRequestsStartedOwnershipOnce() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.connection.publish()
    fixture.connection.publish()

    check(fixture.starts == 1)
    check(fixture.observer.publications == 2)
  }

  private fun aPendingStartSurvivesAttachment() {
    val fixture = Fixture()
    fixture.connection.publish()
    fixture.connection.attach(fixture.observer)
    fixture.connection.publish()

    check(fixture.starts == 1)
    check(fixture.observer.publications == 1)
  }

  private fun anAlreadyStartedServiceNeedsNoStartRequest() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.publish()

    check(fixture.starts == 0)
    check(fixture.observer.publications == 1)
  }

  private fun clearStopsAndAllowsANewStart() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.clear()

    check(fixture.stops == 1)
    check(fixture.observer.clears == 1)

    fixture.connection.publish()
    check(fixture.starts == 1)
  }

  private fun detachResetsTheCurrentService() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.detach(fixture.observer)
    fixture.connection.publish()

    check(fixture.starts == 1)
    check(fixture.observer.publications == 0)
  }

  private fun aLateStartAcknowledgementCannotUndoClear() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.connection.publish()
    fixture.connection.clear()
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.publish()

    check(fixture.starts == 2)
    check(fixture.stops == 1)

    fixture.connection.markStarted(fixture.observer)
    fixture.connection.publish()
    check(fixture.starts == 2)

    fixture.connection.clear()
    fixture.connection.detach(fixture.observer)
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.publish()
    check(fixture.starts == 2)
  }

  private fun aReplacedObserverCannotResetTheCurrentService() {
    val fixture = Fixture()
    val previous = Observer()
    fixture.connection.attach(previous)
    fixture.connection.publish()
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(fixture.observer)
    fixture.connection.detach(previous)
    fixture.connection.publish()

    check(fixture.starts == 1)
    check(previous.publications == 1)
    check(fixture.observer.publications == 1)
  }

  private fun aStaleStartedCallbackCannotMarkTheReplacement() {
    val fixture = Fixture()
    val previous = Observer()
    fixture.connection.attach(previous)
    fixture.connection.attach(fixture.observer)
    fixture.connection.markStarted(previous)
    fixture.connection.publish()

    check(fixture.starts == 1)
    check(fixture.observer.publications == 1)
  }

  private fun aFailedStartCanBeRetried() {
    val fixture = Fixture()
    fixture.connection.attach(fixture.observer)
    fixture.failNextStart = true

    val failure = runCatching { fixture.connection.publish() }.exceptionOrNull()
    check(failure is IllegalStateException)
    check(fixture.starts == 1)

    fixture.connection.publish()
    fixture.connection.publish()
    check(fixture.starts == 2)
    check(fixture.observer.publications == 3)
  }

  private fun sourceChangesOnlyNotifyTheCurrentObserver() {
    val fixture = Fixture()
    val previous = Observer()
    fixture.connection.attach(previous)
    fixture.connection.attach(fixture.observer)
    fixture.connection.sourcesChanged()

    check(previous.sourceChanges == 0)
    check(fixture.observer.sourceChanges == 1)
    check(fixture.starts == 0 && fixture.stops == 0)
  }

  private class Fixture {
    var starts = 0
    var stops = 0
    var failNextStart = false
    val observer = Observer()
    val connection = MediaServiceConnection(
      startService = {
        starts += 1

        if (failNextStart) {
          failNextStart = false
          error("Foreground start rejected")
        }
      },
      stopService = { stops += 1 }
    )
  }

  private class Observer : MediaServiceObserver {
    var publications = 0
    var clears = 0
    var sourceChanges = 0

    override fun applyState() {
      publications += 1
    }

    override fun clearState() {
      clears += 1
    }

    override fun onSourcesChanged() {
      sourceChanges += 1
    }
  }
}
