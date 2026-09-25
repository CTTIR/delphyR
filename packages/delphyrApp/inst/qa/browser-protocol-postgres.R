if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
b<-chromote::ChromoteSession$new();b$Page$navigate('http://127.0.0.1:3873');Sys.sleep(2)
js<-function(code){r<-b$Runtime$evaluate(code);if(!is.null(r$exceptionDetails))stop(r$exceptionDetails$text);r$result$value}
d<-b$DOM$getDocument();node<-b$DOM$querySelector(nodeId=d$root$nodeId,selector='#protocols-file')$nodeId
b$DOM$setFileInputFiles(files=list(normalizePath(Sys.getenv('DELPHYR_PROTOCOL_JSON','.checks/protocol-browser-candidate.json'))),nodeId=node)
Sys.sleep(.7);js("document.getElementById('protocols-validate').click()");Sys.sleep(.5)
x<-js("document.getElementById('protocols-changes').innerText");print(x);stopifnot(length(x)==1,grepl('stopping.max_rounds',x,fixed=TRUE),grepl('3',x,fixed=TRUE),grepl('4',x,fixed=TRUE))
x<-js("document.getElementById('protocols-preview_heading').innerText");stopifnot(length(x)==1,grepl('version 1',x,fixed=TRUE))
js("var reason=document.getElementById('protocols-reason');reason.value='Synthetic future-round extension after exact review.';reason.dispatchEvent(new Event('change',{bubbles:true}));document.getElementById('protocols-confirm').click();document.getElementById('protocols-approve').click()")
Sys.sleep(.5);x<-js("document.getElementById('protocols-status').innerText");print(x);stopifnot(length(x)==1,grepl('New version confirmed: 2',x,fixed=TRUE));b$screenshot(file.path(tempdir(),'delphyr-protocol-amendment.png'));b$close()
