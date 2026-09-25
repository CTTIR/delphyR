if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
b<-chromote::ChromoteSession$new();b$Page$navigate('http://127.0.0.1:3871');Sys.sleep(2)
js<-function(code){r<-b$Runtime$evaluate(code);if(!is.null(r$exceptionDetails))stop(r$exceptionDetails$text);r$result$value}
js("document.querySelectorAll('details').forEach(x=>x.open=true)")
js("for(const [id,value] of [['editorial-source_ref','SYNTHETIC-QA-SOURCE'],['editorial-original','Synthetic original with a fictional identifier SAMPLE-12.']]){const e=document.getElementById(id);e.value=value;e.dispatchEvent(new Event('change',{bubbles:true}))};document.getElementById('editorial-record').click()")
Sys.sleep(.6);x<-js("document.getElementById('editorial-status').textContent");print(x);stopifnot(length(x)==1,grepl('Saved.',x,fixed=TRUE))
js("document.querySelectorAll('details').forEach(x=>x.open=true);const source=document.getElementById('editorial-source').selectize;source.setValue(Object.keys(source.options)[0]);document.getElementById('editorial-kind').selectize.setValue('summary');for(const [id,value] of [['editorial-redacted','Synthetic summary without the fictional identifier.'],['editorial-edit_reason','Remove fictional identifier while preserving the expressed view.']]){const e=document.getElementById(id);e.value=value;e.dispatchEvent(new Event('change',{bubbles:true}))};document.getElementById('editorial-redact').click()")
Sys.sleep(.6);x<-js("document.getElementById('editorial-status').textContent");print(x);stopifnot(length(x)==1,grepl('Saved.',x,fixed=TRUE));b$close()
