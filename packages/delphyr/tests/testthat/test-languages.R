test_that("English, French and German protocol content are explicit supported locales", {
  for(locale in c("en","fr","de")) {
    p<-demo_protocol();p$study$languages<-locale;p$study$default_language<-locale
    expect_true(validate_protocol(p)$valid)
  }
  p$study$languages<-"es";p$study$default_language<-"es"
  expect_false(validate_protocol(p)$valid)
})
test_that("French approved content persists through consent, instrument, import and campaign",{
  skip_if(Sys.getenv("DELPHYR_TEST_DB")!="true","PostgreSQL opt-in")
  r<-connect_repository(host="127.0.0.1",port=55439,dbname="delphyr",user="postgres",environment="test")
  withr::defer(DBI::dbDisconnect(r$con))
  manager<-demo_actor(r,provision_demo_principal(r,paste0("demo-fr-manager-",uid()),TRUE))
  panel<-demo_actor(r,provision_demo_principal(r,paste0("demo-fr-panel-",uid())))
  p<-demo_protocol();p$study$code<-paste0("FR-",uid());p$study$languages<-c("en","fr","de");p$study$default_language<-"fr"
  s<-create_study(r,manager,p,"create")$id
  add_panelist(r,manager,s,panel$principal_id,"professionals","panel")
  consent<-publish_consent(r,manager,s,"Information synthétique. Aucune donnée réelle.","fr","consent")$id
  items<-data.frame(item_code="I001",item_version=1L,locale=c("en","fr","de"),text=c("Synthetic item","Question synthétique","Synthetisches Item"),dimension_code="relevance",scale_code="relevance_9",source_ref="synthetic",required=TRUE,display_order=1L)
  round<-prepare_round(r,manager,s,items,consent,format(Sys.time()+3600,"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),"round")$id
  stored<-query(r,"SELECT texts::text FROM research.round_items WHERE round_id=$1",round)$texts
  expect_identical(jsonlite::fromJSON(stored)$fr,"Question synthétique")
  expect_identical(query(r,"SELECT locale FROM identity.consent_versions WHERE id=$1",consent)$locale,"fr")
  e<-query(r,"SELECT id FROM research.enrollments WHERE round_id=$1",round)$id
  campaign<-prepare_campaign(r,manager,round,e,"invitation","Invitation synthétique","Étude synthétique uniquement.",locale="fr",command_id="campaign")
  expect_identical(query(r,"SELECT locale FROM ops.campaigns WHERE id=$1",campaign$id)$locale,"fr")
  preview<-preview_panel_import(r,manager,s,"external_ref,email,display_name,locale,stakeholder_group\nfrench,french@example.invalid,Synthetic French,fr,professionals")
  expect_true(preview$valid)
  import_panel(r,manager,s,preview,preview$hash,"Synthetic French import approved","import")
  expect_identical(query(r,"SELECT locale FROM identity.panel_contacts WHERE study_id=$1",s)$locale,"fr")
  expect_error(publish_consent(r,manager,s,"Synthetic",c("fr","de"),"invalid"),class="DEL_VALIDATION")
  expect_error(publish_consent(r,manager,s,"Synthetic","es","unsupported"),class="DEL_VALIDATION")
  expect_error(prepare_campaign(r,manager,round,e,"invitation","Synthetic","Synthetic",locale="es",command_id="unsupported"),class="DEL_VALIDATION")
})
