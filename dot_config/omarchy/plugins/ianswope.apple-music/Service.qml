import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "Model.js" as Model

// Finds the one MPRIS player that belongs to Apple Music and nothing else.
//
// A Chromium-family browser publishes a single MPRIS player per browser
// process, covering every tab, and exposes no xesam:url. Bound to that, a
// widget shows whatever the browser is playing and cannot tell Apple Music from
// a video in another tab. Apple Music therefore runs in its own profile, so it
// owns its own browser process and its own bus name; the status helper reports
// which one, by matching the name's owning pid to the process holding our
// profile. Everything below hangs off that single fact.
Item {
  id: root

  property var settings: ({})

  property var status: Model.emptyStatus()
  property bool everLoaded: false
  property string lastError: ""
  property string actionStatus: ""
  property int positionTick: 0
  property bool refreshQueued: false

  readonly property bool running: status.running === true
  readonly property string bus: status.bus || ""

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: findPlayer()

  readonly property bool hasMedia: player !== null && (trackTitle !== "" || trackArtist !== "")
  readonly property bool isPlaying: player !== null && player.isPlaying === true

  readonly property string trackTitle: player ? Model.sanitize(player.trackTitle) : ""
  readonly property string trackArtist: player ? Model.sanitize(player.trackArtist) : ""
  readonly property string trackAlbum: player ? Model.sanitize(player.trackAlbum) : ""
  // Chrome writes the artwork to a local file and hands over a file:// URL, so
  // showing it is a local read rather than a fetch back out to Apple.
  //
  // Only local schemes are accepted. The artwork URL is set by page content, and
  // a page is free to name a remote one; handing that to an Image would make the
  // shell itself fetch whatever address a web page chose.
  readonly property string artUrl: {
    if (!player || !player.trackArtUrl) return ""
    var url = String(player.trackArtUrl)
    if (url.indexOf("file://") === 0) return url
    if (url.indexOf("data:image/") === 0) return url
    return ""
  }

  readonly property bool canGoNext: player !== null && player.canGoNext === true
  readonly property bool canGoPrevious: player !== null && player.canGoPrevious === true
  readonly property bool canToggle: player !== null && player.canTogglePlaying === true

  // Apple Music reports mpris:length as INT64_MAX until it knows the duration,
  // which arrives here as an astronomical number of seconds and renders as
  // 2562047788:00:54. Anything longer than a day is not a track, so it counts as
  // unknown: the elapsed time still runs, the bar and the total stay hidden.
  readonly property real trackLength: {
    var l = player ? Number(player.length) : 0
    if (!isFinite(l) || l <= 0 || l > 86400) return 0
    return l
  }
  readonly property bool lengthKnown: trackLength > 0
  readonly property bool positionKnown: player !== null && player.positionSupported === true
  readonly property real trackPosition: {
    positionTick
    if (!player || !positionKnown) return 0
    var p = Number(player.position)
    return isFinite(p) && p >= 0 ? p : 0
  }

  readonly property string headline: Model.headline({
    running: running, hasMedia: hasMedia, isPlaying: isPlaying, bus: bus
  })

  readonly property string barLabel: showTrackInBar && hasMedia
    ? Model.barLabel(trackTitle, trackArtist, maxBarChars)
    : ""

  readonly property bool showTrackInBar: setting("showTrackInBar", true) === true
  readonly property bool showArtwork: setting("showArtwork", true) === true
  readonly property int maxBarChars: intSetting("maxBarChars", 28, 8, 80)
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 3, 120)

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string statusHelper: pluginDir + "/bin/omarchy-apple-music-status"
  readonly property string launchHelper: pluginDir + "/bin/omarchy-apple-music"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function findPlayer() {
    if (bus === "") return null
    var list = players || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].dbusName || "") === bus) return list[i]
    }
    return null
  }

  // A read arriving while one is in flight is remembered rather than dropped.
  // The dropped case loses exactly the interesting transition, because a bus
  // name appearing is what triggers the second read.
  function refresh() {
    if (statusProcess.running) { refreshQueued = true; return }
    refreshQueued = false
    statusProcess.command = ["bash", statusHelper]
    statusProcess.running = true
  }

  function note(text) {
    actionStatus = Model.sanitize(text)
    actionStatusTimer.restart()
  }

  // ------------------------------------------------------------- actions

  // One entry point for both cases: the helper focuses the window when it is
  // already open and starts it when it is not, so the widget does not have to
  // care which.
  function open() {
    Quickshell.execDetached(["bash", launchHelper])
    note(running ? "Focusing Apple Music" : "Opening Apple Music…")
    settleTimer.restart()
  }

  function playPause() {
    if (!player) { open(); return }
    if (canToggle) player.togglePlaying()
    else note("Apple Music is not accepting playback commands")
  }

  function next() {
    if (!player || !canGoNext) return
    player.next()
  }

  function previous() {
    if (!player || !canGoPrevious) return
    player.previous()
  }

  // A new bus name appearing or disappearing is the interesting event: it is
  // what happens when playback starts, stops, or the window closes. Re-reading
  // on that change is what keeps the widget prompt without a fast poll.
  onPlayersChanged: refresh()

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A cold start has to create the profile and paint a window, which takes
  // longer than one interval, so the seconds after a launch are checked harder.
  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 8) running = false
    }
  }

  // MPRIS position is read on demand rather than pushed, so the progress line
  // needs its own tick. Only while something is actually playing.
  Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying && root.positionKnown
    onTriggered: root.positionTick++
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(statusStdout.text || "")
      if (out.trim() !== "") {
        var parsed = Model.parseStatus(out)
        root.status = parsed
        root.everLoaded = true
        root.lastError = parsed.ok ? "" : parsed.error
        return
      }
      root.everLoaded = true
      root.status = Model.emptyStatus()
      root.lastError = Model.sanitize(statusStderr.text) || ("Could not run " + root.statusHelper)
    }
    onRunningChanged: if (!running && root.refreshQueued) Qt.callLater(root.refresh)
  }
}
