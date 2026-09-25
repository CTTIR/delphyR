# Run preview-postgres.R first with a new synthetic fixture. Requires chromote.
Sys.setenv(CHROMOTE_CHROME = Sys.getenv("CHROMOTE_CHROME", "/usr/bin/chromium"))
b <- chromote::ChromoteSession$new()
js <- function(code) {
  result <- b$Runtime$evaluate(code)
  if (!is.null(result$exceptionDetails)) stop(result$exceptionDetails$text)
  result$result$value
}
wait_for <- function(code) {
  for (attempt in seq_len(100)) {
    if (isTRUE(js(code))) return(invisible(TRUE))
    Sys.sleep(.1)
  }
  stop("Browser condition was not met: ", code)
}
b$Page$navigate("http://127.0.0.1:3868")
wait_for("document.getElementById('panel-load') !== null && document.getElementById('panel-enrollment').value !== ''")
stopifnot(identical(js("document.documentElement.lang"), "en"))
js("document.getElementById('panel-load').click()")
wait_for("document.getElementById('panel-item_1_1-value') !== null")
consent <- js("document.querySelector('.del-consent').textContent")
js("document.getElementById('panel-consent_check').click();document.getElementById('panel-consent').click()")
wait_for("document.getElementById('panel-status').textContent.includes('Consent saved.')")
js("document.getElementById('panel-item_1_1-kind').selectize.setValue('answered');document.getElementById('panel-item_1_1-value').selectize.setValue('7')")
wait_for("document.getElementById('panel-item_1_1-status').textContent.includes('Unsaved')")
for (language in c("fr", "de", "en")) {
  js(sprintf("document.getElementById('language').selectize.setValue('%s')", language))
  wait_for(sprintf("document.documentElement.lang === '%s'", language))
  Sys.sleep(.3)
  stopifnot(identical(js("document.getElementById('panel-item_1_1-value').value"), "7"))
  stopifnot(identical(js("document.querySelector('.del-consent').textContent"), consent))
  title <- js("document.getElementById('panel-item_1_1-title').textContent")
  stopifnot(grepl(switch(language, fr = "Exemple synth", de = "Synthetisches Beispielitem", en = "Synthetic example item"), title, fixed = TRUE))
  stopifnot(identical(js("document.querySelectorAll('.shiny-output-error').length"), 0L))
}
js("document.getElementById('language').selectize.setValue('fr')")
wait_for("document.documentElement.lang === 'fr'")
js("document.getElementById('panel-item_1_1-save').click()")
wait_for("document.querySelector('#panel-item_1_1-save_status .del-status--saved') !== null")
french <- js("document.getElementById('panel-item_1_1-status').textContent")
stopifnot(grepl("Enregistr", french, fixed = TRUE))
js("document.getElementById('language').selectize.setValue('en')")
wait_for("document.getElementById('panel-item_1_1-status').textContent.startsWith('Saved:')")
for (mobile in c(FALSE, TRUE)) {
  b$Emulation$setDeviceMetricsOverride(width = if (mobile) 390 else 1280, height = if (mobile) 844 else 900, deviceScaleFactor = 1, mobile = mobile)
  Sys.sleep(.2)
  stopifnot(isTRUE(js("document.documentElement.scrollWidth <= innerWidth")))
}
js("document.getElementById('language').selectize.setValue('fr')")
wait_for("document.documentElement.lang === 'fr'")
js("document.getElementById('panel-confirm').click();document.getElementById('panel-submit').click()")
wait_for("document.getElementById('panel-receipt').textContent.length > 0")
stopifnot(grepl("confirm", js("document.getElementById('panel-receipt').textContent"), fixed = TRUE))
print(list(languages = c("en", "fr", "de"), saved = french, pending_value_preserved = TRUE, approved_consent_unchanged = TRUE, mobile_overflow = FALSE))
b$close()
