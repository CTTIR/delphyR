# Run preview.R first with a fresh synthetic fixture. Requires chromote.
local({
  b <- chromote::ChromoteSession$new()
  on.exit(b$close())
  js <- function(code) {
    z <- b$Runtime$evaluate(code, returnByValue = TRUE)
    if (!is.null(z$exceptionDetails)) stop(z$exceptionDetails$text)
    z$result$value
  }
  # Await observable UI states; cold Shiny startup can exceed a fixed sleep.
  await <- function(code, seconds = 120) {
    deadline <- Sys.time() + seconds
    repeat {
      if (isTRUE(js(code))) return(invisible(TRUE))
      if (Sys.time() >= deadline) stop("Timed out waiting for: ", code)
      Sys.sleep(0.1)
    }
  }
  b$Page$navigate("http://127.0.0.1:3867")
  await("Boolean(document.getElementById('panel-enrollment') && document.getElementById('panel-enrollment').value === 'own')")
  js("document.getElementById('panel-load').click()")
  await("Boolean(document.getElementById('panel-consent_check'))")
  await("Boolean(document.querySelector('#panel-slot_1-form fieldset'))")
  stopifnot(isTRUE(js("document.querySelector('#panel-slot_1-form fieldset').disabled")))
  js("document.getElementById('panel-consent_check').click(); document.getElementById('panel-consent').click()")
  await("Boolean(document.querySelector('#panel-slot_1-form fieldset') && !document.querySelector('#panel-slot_1-form fieldset').disabled)")
  # Consent replaces the read-only block: controls have a new generation id.
  value <- "document.querySelector('[id^=\"panel-item_\"][id$=\"-value\"]')"
  save <- "document.querySelector('[id^=\"panel-item_\"][id$=\"-save\"]')"
  stopifnot(identical(js(paste0(value, ".value")), ""))
  js(paste0("(function(){var x=", value, ";x.value='7';x.dispatchEvent(new Event('change',{bubbles:true}));return true;})()"))
  await("Boolean(document.getElementById('panel-card_1-status') && document.getElementById('panel-card_1-status').textContent.includes('Not saved yet.'))")
  js("(function(){var x=document.getElementById('language');x.value='de';x.dispatchEvent(new Event('change',{bubbles:true}));return true;})()")
  await("Boolean(document.getElementById('panel-card_1-status') && document.getElementById('panel-card_1-status').textContent.includes('Noch nicht gespeichert.'))")
  stopifnot(identical(js(paste0(value, ".value")), "7"))
  stopifnot(grepl("Wie relevant ist eine klare Kommunikation", js("document.getElementById('panel-slot_1-title').textContent"), fixed = TRUE))
  js(paste0(save, ".click()"))
  await("Boolean(document.getElementById('panel-card_1-status') && document.getElementById('panel-card_1-status').textContent.includes('Gespeichert'))")
  print(js("document.getElementById('panel-card_1-status').textContent"))
  js("document.getElementById('panel-confirm').click();document.getElementById('panel-submit').click()")
  await("Boolean(document.querySelector('#panel-receipt .del-ref') && document.querySelector('#panel-receipt .del-ref').title === 'synthetic-submission')")
  receipt <- js("document.getElementById('panel-receipt').textContent")
  stopifnot(grepl("25. Sept. 2026, 14:00 (Europe/Berlin, UTC+2)", receipt, fixed = TRUE))
  print(receipt)
})
