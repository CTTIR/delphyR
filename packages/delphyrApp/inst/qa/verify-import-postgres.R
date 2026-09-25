if (!identical(Sys.getenv("DELPHYR_TEST_DB"), "true")) stop("Set DELPHYR_TEST_DB=true to opt in.")
.libPaths(c(normalizePath('.R-library'),.libPaths()));pkgload::load_all('packages/delphyr',quiet=TRUE)
f<-readRDS(Sys.getenv('DELPHYR_IMPORT_FIXTURE','.checks/panel-import-browser-fixture.rds'))
w<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='development',artifact_root=file.path(getwd(),'.artifacts'))
count<-function(table)DBI::dbGetQuery(w$con,paste0('SELECT count(*) AS n FROM ',table,' WHERE study_id=$1'),params=list(f$study_id))$n
stopifnot(count('identity.panel_contacts')==2,count('identity.panel_invitation_drafts')==2,count('identity.panel_import_receipts')==1,count('research.panelists')==2,count('research.enrollments')==2)
id<-DBI::dbGetQuery(w$con,'SELECT id FROM identity.panel_import_receipts WHERE study_id=$1',params=list(f$study_id))$id
r<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='delphyr_runtime',environment='development',artifact_root=file.path(getwd(),'.artifacts'))
receipt<-get_panel_import_receipt(r,demo_actor(r,f$manager$principal_id),id)
stopifnot(receipt$receipt$accepted_rows==2,length(receipt$invitation_ids)==2,!any(c('email','display_name') %in% names(receipt$receipt)))
print(list(imported_contacts=2L,unbound_invitation_drafts=2L,unchanged_panelists=2L,unchanged_enrollments=2L,receipt=receipt$receipt$id))
DBI::dbDisconnect(r$con);DBI::dbDisconnect(w$con)
