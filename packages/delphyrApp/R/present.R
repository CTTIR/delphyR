# Presentation helpers. Every screen shows moments, numbers, references and
# codes in the same way, so that a person never reads a database format, a
# raw code or "NA" (docs/adr/029-presentation-conventions.md).

# The sign for a value that does not exist or is not shown.
no_value <- "\u2014"

# Month abbreviations of the interface language, independent of the locale of
# the server.
month_abbreviations <- function(lang) {
  switch(lang,
    fr = c("janv.", "f\u00e9vr.", "mars", "avr.", "mai", "juin", "juil.", "ao\u00fbt", "sept.", "oct.", "nov.", "d\u00e9c."),
    de = c("Jan.", "Feb.", "M\u00e4rz", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."),
    c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
  )
}

# Reads moments as they arrive from the database or a service: POSIXct, epoch
# seconds, ISO text with T or a space, fractions of seconds, Z or an offset of
# the form +HH, +HHMM or +HH:MM. A date alone is midnight UTC. Anything else
# becomes NA.
parse_moment <- function(x) {
  if (inherits(x, "POSIXt")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  if (is.numeric(x)) {
    return(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"))
  }
  x <- trimws(as.character(x))
  out <- as.POSIXct(rep(NA_real_, length(x)), origin = "1970-01-01", tz = "UTC")
  pattern <- "^(\\d{4}-\\d{2}-\\d{2})(?:[T ](\\d{2}:\\d{2})(?::(\\d{2}))?(?:\\.\\d+)?\\s*(Z|[+-]\\d{2}(?::?\\d{2})?)?)?$"
  parts <- regmatches(x, regexec(pattern, x, perl = TRUE))
  for (i in seq_along(x)) {
    p <- parts[[i]]
    if (!length(p) || is.na(x[i])) next
    clock <- if (nzchar(p[3])) p[3] else "00:00"
    seconds <- if (nzchar(p[4])) p[4] else "00"
    base <- as.POSIXct(paste0(p[2], " ", clock, ":", seconds), format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
    zone <- p[5]
    shift <- 0
    if (nzchar(zone) && zone != "Z") {
      digits <- gsub("[^0-9]", "", zone)
      minutes <- if (nchar(digits) >= 4L) as.integer(substr(digits, 3, 4)) else 0L
      shift <- (if (startsWith(zone, "-")) -1 else 1) * (as.integer(substr(digits, 1, 2)) * 3600 + minutes * 60)
    }
    out[i] <- base - shift
  }
  out
}

# A moment in the study's time zone: date, time, and the zone with its UTC
# offset, so that the hour that occurs twice in autumn stays unambiguous.
#   en "8 Oct 2026, 19:49 (Europe/Berlin, UTC+2)"
#   fr "8 oct. 2026, 19:49 (Europe/Berlin, UTC+2)"
#   de "8. Okt. 2026, 19:49 (Europe/Berlin, UTC+2)"
format_moment <- function(x, zone = "UTC", lang = "en", with_zone = TRUE) {
  moments <- parse_moment(x)
  if (is.null(zone) || length(zone) != 1L || is.na(zone) || !nzchar(zone) || !zone %in% known_zones()) zone <- "UTC"
  out <- rep(no_value, length(moments))
  ok <- !is.na(moments)
  if (!any(ok)) {
    return(out)
  }
  local <- as.POSIXlt(moments[ok], tz = zone)
  month <- month_abbreviations(lang)[local$mon + 1L]
  date <- if (identical(lang, "de")) sprintf("%d. %s %d", local$mday, month, local$year + 1900L) else sprintf("%d %s %d", local$mday, month, local$year + 1900L)
  clock <- sprintf("%02d:%02d", local$hour, local$min)
  offset <- format(moments[ok], "%z", tz = zone)
  hours <- as.integer(substr(offset, 2, 3))
  minutes <- substr(offset, 4, 5)
  utc <- ifelse(offset == "+0000", "UTC", paste0("UTC", substr(offset, 1, 1), hours, ifelse(minutes == "00", "", paste0(":", minutes))))
  where <- if (zone == "UTC") "(UTC)" else sprintf("(%s, %s)", zone, utc)
  out[ok] <- if (with_zone) paste0(date, ", ", clock, " ", where) else paste0(date, ", ", clock)
  out
}
known_zones <- local({
  zones <- NULL
  function() {
    if (is.null(zones)) zones <<- OlsonNames()
    zones
  }
})

# Numbers with the decimal sign of the interface language; at most `digits`
# decimals, without trailing zeros. Missing values are a dash.
format_number <- function(x, lang = "en", digits = 1L) {
  x <- suppressWarnings(as.numeric(x))
  out <- formatC(round(x, digits), format = "f", digits = digits, drop0trailing = TRUE)
  out <- sub("^-0$", "0", out)
  if (lang %in% c("fr", "de")) out <- chartr(".", ",", out)
  out[is.na(x)] <- no_value
  out
}
# A proportion as a whole percentage: "75%" in English, "75 %" in French and
# German (with a no-break space).
format_percent <- function(x, lang = "en") {
  x <- suppressWarnings(as.numeric(x))
  out <- paste0(format_number(100 * x, lang, 0L), if (lang %in% c("fr", "de")) "\u00a0%" else "%")
  out[is.na(x)] <- no_value
  out
}

# The first characters of an identifier. The full value belongs in a title
# attribute or in an export, never in the running text.
short_ref <- function(x, n = 8L) {
  x <- as.character(x)
  out <- substr(x, 1L, n)
  out[is.na(x) | !nzchar(x)] <- no_value
  out
}
ref_tag <- function(x, n = 8L) shiny::tags$span(class = "del-ref", title = x, short_ref(x, n))

# A code from the protocol without a label of its own, readable:
# "public_contributors" becomes "Public contributors". Study content is never
# translated.
humanize_code <- function(x) {
  x <- as.character(x)
  words <- gsub("_", " ", x, fixed = TRUE)
  out <- paste0(toupper(substr(words, 1L, 1L)), substring(words, 2L))
  out[is.na(x) | !nzchar(x)] <- no_value
  out
}

# A moment is entered as a date and a time of day in the study's time zone;
# the offset from UTC is computed, never typed. `id` is the (namespaced) stem:
# the inputs are <id>_date and <id>_time.
moment_input <- function(id, label, zone, lang, value = NULL) {
  if (is.null(zone) || length(zone) != 1L || is.na(zone) || !zone %in% known_zones()) zone <- "UTC"
  moment <- if (length(value)) parse_moment(value)[1] else NA
  local <- if (!is.na(moment)) as.POSIXlt(moment, tz = zone) else NULL
  date <- suppressWarnings(shiny::dateInput(paste0(id, "_date"), tr(lang, "Datum (JJJJ-MM-TT)", "Date (YYYY-MM-DD)"), value = if (is.null(local)) NA else format(local, "%Y-%m-%d"), language = lang, weekstart = 1L))
  # The field's own English tooltip is dropped; the label names the format.
  date <- htmltools::tagQuery(date)$find("input")$removeAttrs("title")$allTags()
  shiny::tags$fieldset(
    class = "del-moment",
    shiny::tags$legend(label),
    date,
    shiny::textInput(paste0(id, "_time"), tr(lang, "Uhrzeit (24 Stunden, HH:MM)", "Time (24-hour, HH:MM)"), value = if (is.null(local)) "" else sprintf("%02d:%02d", local$hour, local$min)),
    shiny::tags$p(class = "del-note", paste(tr(lang, "Zeitzone der Studie:", "Time zone of the study:"), zone))
  )
}
# Reads a date and a time of day in a zone. Returns list(value = ISO 8601 text
# with the offset) or list(error = "format" | "nonexistent" | "ambiguous"): a
# time skipped when the clocks go forward does not exist, one repeated when
# they go back is ambiguous; neither is guessed.
read_moment <- function(date, time, zone) {
  if (is.null(zone) || length(zone) != 1L || is.na(zone) || !zone %in% known_zones()) zone <- "UTC"
  date <- if (inherits(date, "Date")) format(date, "%Y-%m-%d") else as.character(date)
  time <- as.character(time)
  if (length(date) != 1L || length(time) != 1L || is.na(date) || is.na(time)) {
    return(list(error = "format"))
  }
  date <- trimws(date)
  time <- trimws(time)
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", date) || !grepl("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", time)) {
    return(list(error = "format"))
  }
  clock <- as.integer(strsplit(time, ":", fixed = TRUE)[[1]])
  time <- sprintf("%02d:%02d", clock[1], clock[2])
  wall <- as.POSIXct(paste(date, time), format = "%Y-%m-%d %H:%M", tz = "UTC")
  if (is.na(wall) || format(wall, "%Y-%m-%d") != date) {
    return(list(error = "format"))
  }
  offsets <- unique(as.POSIXlt(wall + c(-1, 1) * 86400, tz = zone)$gmtoff)
  candidates <- wall - offsets
  candidates <- candidates[format(candidates, "%Y-%m-%d %H:%M", tz = zone) == paste(date, time)]
  if (!length(candidates)) {
    return(list(error = "nonexistent"))
  }
  if (length(unique(as.numeric(candidates))) > 1L) {
    return(list(error = "ambiguous"))
  }
  offset <- as.POSIXlt(candidates[1], tz = zone)$gmtoff
  sign <- if (offset < 0) "-" else "+"
  list(value = sprintf("%sT%s:00%s%02d:%02d", date, time, sign, abs(offset) %/% 3600L, (abs(offset) %% 3600L) %/% 60L))
}
moment_error_text <- function(code, lang) {
  switch(code,
    nonexistent = tr(lang, "Diese Uhrzeit gibt es an diesem Tag in der Zeitzone der Studie nicht, weil die Uhren vorgestellt werden. Bitte eine andere Uhrzeit w\u00e4hlen.", "This time does not exist on that day in the study's time zone because the clocks go forward. Choose another time."),
    ambiguous = tr(lang, "Diese Uhrzeit kommt an diesem Tag in der Zeitzone der Studie zweimal vor, weil die Uhren zur\u00fcckgestellt werden. Bitte eine andere Uhrzeit w\u00e4hlen.", "This time occurs twice on that day in the study's time zone because the clocks go back. Choose another time."),
    tr(lang, "Bitte ein Datum (JJJJ-MM-TT) und eine Uhrzeit (HH:MM) angeben.", "Enter a date (YYYY-MM-DD) and a time (HH:MM).")
  )
}
