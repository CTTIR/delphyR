if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
.libPaths(c(normalizePath('.R-library'),.libPaths()))
pkgload::load_all('packages/delphyr',quiet=TRUE);pkgload::load_all('packages/delphyrApp',quiet=TRUE)
path<-Sys.getenv('DELPHYR_EDITORIAL_FIXTURE','.checks/editorial-campaign-fixture.rds')
dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
if(!file.exists(path)) {
 r<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='development',artifact_root=file.path(getwd(),'.artifacts'))
 migrate_repository(r)
 f<-demo_study(r,n=2L,item_count=1L)
 f$editor<-demo_actor(r,provision_demo_principal(r,paste0('demo-qa-editor-',uuid::UUIDgenerate())))
 set_capability(r,f$manager,f$study_id,f$editor$principal_id,'edit',TRUE,uuid::UUIDgenerate())
 saveRDS(f,path);DBI::dbDisconnect(r$con)
}
f<-readRDS(path);args<-commandArgs(trailingOnly=TRUE);role<-if(length(args))args[1] else 'editor'
r<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='delphyr_runtime',environment='development',artifact_root=file.path(getwd(),'.artifacts'))
actor<-demo_actor(r,if(role=='editor') f$editor$principal_id else f$manager$principal_id)
ns<-asNamespace('delphyr');services<-as.list(ns)[vapply(as.list(ns),is.function,logical(1))]
call<-function(name,...)services[[name]](r,actor,...)
ui<-shiny::fluidPage(theme=bslib::bs_theme(version=5),shiny::tags$style(shiny::HTML(delphyrApp:::app_css())),shiny::tags$div(class='del-wrap',delphyrApp:::editorial_ui('editorial'),delphyrApp:::communications_ui('communications')))
server<-function(input,output,session){delphyrApp:::editorial_server('editorial',function()f$study_id,function()'en',call,services);delphyrApp:::communications_server('communications',function()f$study_id,function()'en',call,services)}
shiny::runApp(shiny::shinyApp(ui,server),host='127.0.0.1',port=if(role=='editor')3871L else 3872L,launch.browser=FALSE)
