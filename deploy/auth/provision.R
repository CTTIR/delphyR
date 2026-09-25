# Trusted local fixture provisioning, never run from a browser session.
.libPaths(c(normalizePath('.R-library'),.libPaths()))
pkgload::load_all('packages/delphyr',quiet=TRUE)
credentials<-jsonlite::fromJSON('.local/auth/credentials.json')
r<-delphyr::connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='test')
fixture_path<-'.local/auth/study-fixture.rds'
if(file.exists(fixture_path)) f<-readRDS(fixture_path) else {
  f<-delphyr::demo_study(r,n=2L,item_count=2L,code=paste0('AUTH-',substr(uuid::UUIDgenerate(),1,8)))
  saveRDS(f,fixture_path)
}
f$manager<-delphyr::demo_actor(r,f$manager$principal_id)
p<-DBI::dbGetQuery(r$con,'INSERT INTO identity.principals(id,issuer,subject,can_create) VALUES($1,$2,$3,false) ON CONFLICT(issuer,subject) DO UPDATE SET subject=EXCLUDED.subject RETURNING id',params=list(uuid::UUIDgenerate(),'http://127.0.0.1:4190/realms/delphyr',credentials$subject))
for(cap in c('manage','analyse','export','coordinate','edit'))
  delphyr::set_capability(r,f$manager,f$study_id,p$id,cap,TRUE,paste0('auth-',cap))
writeLines(jsonlite::toJSON(list(principal_id=p$id,study_id=f$study_id),auto_unbox=TRUE),'.local/auth/identity.json')
DBI::dbDisconnect(r$con)
cat('Synthetic issuer/subject mapping and study capabilities provisioned.\n')
if(file.exists('.local/auth/second-credentials.json')) {
  r<-delphyr::connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='test')
  second<-jsonlite::fromJSON('.local/auth/second-credentials.json')
  invisible(DBI::dbGetQuery(r$con,'INSERT INTO identity.principals(id,issuer,subject,can_create) VALUES($1,$2,$3,false) ON CONFLICT(issuer,subject) DO UPDATE SET subject=EXCLUDED.subject RETURNING id',params=list(uuid::UUIDgenerate(),'http://127.0.0.1:4190/realms/delphyr',second$subject)))
  DBI::dbDisconnect(r$con)
}
