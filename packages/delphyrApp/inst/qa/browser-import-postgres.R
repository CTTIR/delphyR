if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
b<-chromote::ChromoteSession$new();b$Page$navigate('http://127.0.0.1:3874');Sys.sleep(2)
js<-function(code){r<-b$Runtime$evaluate(code);if(!is.null(r$exceptionDetails))stop(r$exceptionDetails$text);r$result$value}
upload<-function(path){d<-b$DOM$getDocument();node<-b$DOM$querySelector(nodeId=d$root$nodeId,selector='#panel_import-file')$nodeId;b$DOM$setFileInputFiles(files=list(normalizePath(path)),nodeId=node);Sys.sleep(.6)}
upload('.checks/panel-import-duplicate.csv');js("document.getElementById('panel_import-preview').click()");Sys.sleep(.5)
x<-js("document.getElementById('panel_import-issues').innerText");print(x);stopifnot(length(x)==1,grepl('Duplicate in this file',x,fixed=TRUE))
x<-js("document.getElementById('panel_import-status').innerText");stopifnot(grepl('Import blocked',x,fixed=TRUE))
upload('.checks/panel-import-browser.csv');js("document.getElementById('panel_import-preview').click()");Sys.sleep(.5)
x<-js("document.getElementById('panel_import-status').innerText");print(x);stopifnot(length(x)==1,grepl('Preview passed validation',x,fixed=TRUE))
js("var reason=document.getElementById('panel_import-reason');reason.value='Two synthetic contacts reviewed exactly; no account binding.';reason.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('panel_import-confirm').click();document.getElementById('panel_import-approve').click()")
Sys.sleep(.5);x<-js("document.getElementById('panel_import-receipt').innerText");print(x);stopifnot(length(x)==1,grepl('2 contacts imported; 2 unbound invitation drafts.',x,fixed=TRUE));b$screenshot(file.path(tempdir(),'delphyr-panel-import.png'));b$close()
