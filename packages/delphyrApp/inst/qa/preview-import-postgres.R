if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
.libPaths(c(normalizePath('.R-library'),.libPaths()));pkgload::load_all('packages/delphyr',quiet=TRUE);pkgload::load_all('packages/delphyrApp',quiet=TRUE)
fixture_path<-Sys.getenv('DELPHYR_IMPORT_FIXTURE','.checks/panel-import-browser-fixture.rds')
dir.create(dirname(fixture_path),recursive=TRUE,showWarnings=FALSE)
if(!file.exists(fixture_path)) {
 admin<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='development',artifact_root=file.path(getwd(),'.artifacts'))
 f<-demo_study(admin,n=2L,item_count=1L);saveRDS(f,fixture_path);DBI::dbDisconnect(admin$con)
}
f<-readRDS(fixture_path)
header<-'external_ref,email,display_name,locale,stakeholder_group\n'
rows<-c('QA-IMPORT-1,first@example.invalid,Synthetic First,en,professionals','QA-IMPORT-2,second@example.invalid,Synthetic Second,en,public_contributors')
writeLines(paste0(header,paste(rows,collapse='\n')),'.checks/panel-import-browser.csv')
writeLines(paste0(header,paste(rep(rows[1],2),collapse='\n')),'.checks/panel-import-duplicate.csv')
r<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='delphyr_runtime',environment='development',artifact_root=file.path(getwd(),'.artifacts'));a<-demo_actor(r,f$manager$principal_id)
ns<-asNamespace('delphyr');services<-as.list(ns)[vapply(as.list(ns),is.function,logical(1))];call<-function(name,...)services[[name]](r,a,...)
ui<-shiny::fluidPage(theme=bslib::bs_theme(version=5,primary='#0e6e78'),shiny::tags$style(shiny::HTML(delphyrApp:::app_css())),shiny::tags$div(class='del-wrap',delphyrApp:::panel_import_ui('panel_import')))
server<-function(input,output,session)delphyrApp:::panel_import_server('panel_import',function()f$study_id,function()'en',call,services)
shiny::runApp(shiny::shinyApp(ui,server),host='127.0.0.1',port=3874L,launch.browser=FALSE)
