// Formatting and text handling for the Apple Music panel. The status script
// reports which browser process and which MPRIS name belong to us; everything
// about how that reads on screen is here.

// Track metadata arrives from a web page by way of the media session, so it is
// untrusted text. QML's Text defaults to AutoText, which renders anything
// resembling markup as rich text and fetches what it references, so a track
// titled `<img src="http://host/x">` would make the shell issue that request.
// Cleaned at this one boundary, before any component sees it.
var MAX_TEXT = 200

function sanitize(value) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "")
  s = s.replace(/[\x00-\x1f\x7f]/g, " ")
  s = s.replace(/\s+/g, " ").trim()
  if (s.length > MAX_TEXT) s = s.substring(0, MAX_TEXT - 1) + "…"
  return s
}

function emptyStatus() {
  return { ok: false, error: "", running: false, pid: 0, bus: "", profile: "" }
}

function parseStatus(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return emptyStatus()
  try {
    var parsed = JSON.parse(text)
    return {
      ok: true,
      error: "",
      running: parsed.running === true,
      pid: parseInt(parsed.pid, 10) > 0 ? parseInt(parsed.pid, 10) : 0,
      bus: parsed.bus ? String(parsed.bus) : "",
      profile: parsed.profile ? String(parsed.profile) : ""
    }
  } catch (e) {
    var empty = emptyStatus()
    empty.error = sanitize(String(e))
    return empty
  }
}

// Never returns more than `max` characters. Returning the whole string when the
// budget is too small for an ellipsis, which is the obvious shortcut, is how a
// caller ends up rendering far more than it asked for.
function truncate(value, max) {
  var s = sanitize(value)
  var limit = parseInt(max, 10)
  if (!isFinite(limit) || limit <= 0) return ""
  if (s.length <= limit) return s
  if (limit < 4) return s.substring(0, limit)
  return s.substring(0, limit - 1) + "…"
}

// The bar has one line and no room to lose the title to a long artist name, so
// the title keeps two thirds of the budget and the artist takes what is left.
function barLabel(title, artist, max) {
  var t = sanitize(title)
  var a = sanitize(artist)
  var limit = parseInt(max, 10)
  if (!isFinite(limit) || limit < 8) limit = 28
  if (t === "") return ""
  if (a === "") return truncate(t, limit)

  var separator = " · "
  var budget = limit - separator.length
  var titleBudget = Math.max(6, Math.floor(budget * 0.6))
  var artistBudget = budget - titleBudget

  // Test the budget, not the result. A budget under four characters cannot hold
  // a meaningful artist, and asking for one anyway is what produced labels
  // longer than the limit: give the whole budget to the title instead.
  if (artistBudget < 4) return truncate(t, limit)

  return truncate(t, titleBudget) + separator + truncate(a, artistBudget)
}

// MPRIS carries microseconds on the wire, but Quickshell hands position and
// length over already converted to seconds, so this takes seconds. A track runs
// minutes, so hours only appear when the source is really a mix or a radio show.
function formatDuration(seconds) {
  var total = Math.floor(Number(seconds))
  if (!isFinite(total) || total < 0) return ""
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var seconds = total % 60
  var pad = function(n) { return n < 10 ? "0" + n : String(n) }
  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(seconds)
  return minutes + ":" + pad(seconds)
}

function progressFraction(position, length) {
  var p = Number(position)
  var l = Number(length)
  if (!isFinite(p) || !isFinite(l) || l <= 0) return 0
  return Math.max(0, Math.min(1, p / l))
}

// One line for the panel header and the bar tooltip. "Running" without a track
// is worth saying: it means the window is open but nothing has played yet, which
// is also the state a fresh profile sits in before signing in.
function headline(state) {
  if (!state) return "Not running"
  if (!state.running) return "Not running"
  if (!state.hasMedia) return state.bus === "" ? "Open, nothing playing" : "Ready"
  return state.isPlaying ? "Playing" : "Paused"
}
