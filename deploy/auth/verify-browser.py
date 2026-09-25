#!/usr/bin/env python3
"""Real local OIDC + direct Shiny qualification; never print credentials/cookies."""
import json,subprocess,time
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright,TimeoutError as BrowserTimeout
root=Path(__file__).resolve().parents[2];private=root/'.local/auth'
creds=json.loads((private/'credentials.json').read_text())
second=json.loads((private/'second-credentials.json').read_text())
identity=json.loads((private/'identity.json').read_text())
evidence={'backend':'direct shiny::runApp; stock Shiny Server OSS remains unqualified','checks':{}}
def check(name,value):
 evidence['checks'][name]=bool(value)
 if not value: raise AssertionError(name)
def database(active=None):
 code='''.libPaths(c(normalizePath('.R-library'),.libPaths()));
 c<-jsonlite::fromJSON('.local/auth/identity.json');
 con<-DBI::dbConnect(RPostgres::Postgres(),host='127.0.0.1',port=55439,dbname='delphyr',user='postgres');
 '''
 if active is not None:
  code+="invisible(DBI::dbExecute(con,'UPDATE identity.principals SET active=$1 WHERE id=$2',params=list("+('TRUE' if active else 'FALSE')+",c$principal_id)));"
 code+="cat(DBI::dbGetQuery(con,'SELECT state FROM research.rounds WHERE study_id=$1 ORDER BY number',params=list(c$study_id))$state,sep=',');DBI::dbDisconnect(con)"
 return subprocess.run(['Rscript','-e',code],cwd=root,check=True,capture_output=True,text=True).stdout
http=requests.Session();http.trust_env=False
response=http.get('http://127.0.0.1:4189/',allow_redirects=False,timeout=5)
check('unauthenticated_redirect',response.status_code==302)
response=http.get('http://127.0.0.1:4189/',headers={'X-Forwarded-User':creds['subject'],'X-Delphyr-Gateway':'forged'},allow_redirects=False,timeout=5)
check('unauthenticated_forged_headers_rejected',response.status_code==302)
response=http.get('http://127.0.0.1:4189/',headers={'Cookie':'_oauth2_proxy=forged'},allow_redirects=False,timeout=5)
check('forged_cookie_rejected',response.status_code==302)
response=http.get('http://127.0.0.1:4189/oauth2/callback?code=forged&state=forged',allow_redirects=False,timeout=5)
check('callback_without_valid_csrf_rejected',response.status_code in (400,403,500))
try:
 response=http.get('http://172.30.246.3:8080/',timeout=3)
 check('direct_internal_gateway_rejected',response.status_code==403)
except requests.RequestException: check('direct_internal_gateway_rejected',True)
inspect=json.loads(subprocess.run(['docker','inspect','delphyr-auth-app'],check=True,capture_output=True,text=True).stdout)[0]
check('application_has_no_published_port',not inspect['HostConfig'].get('PortBindings'))

def login(context,credential):
 page=context.new_page();page.goto('http://127.0.0.1:4189/',wait_until='networkidle')
 page.locator('#username').fill(credential['username']);page.locator('#password').fill(credential['password'])
 page.locator('#kc-login').click();page.wait_for_url('http://127.0.0.1:4189/')
 page.wait_for_selector('#banner');page.wait_for_timeout(1000)
 return page
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 manager_context=browser.new_context(extra_http_headers={'X-Forwarded-User':second['subject'],'X-Delphyr-Gateway':'browser-forgery'})
 page=login(manager_context,creds)
 page.wait_for_function("document.querySelector('#study').value !== ''")
 check('real_oidc_websocket_database_mapping',page.locator('#study').input_value()==identity['study_id'])
 check('authenticated_subject_header_spoof_does_not_switch_identity',page.locator('#management-transition').count()==1)
 page.screenshot(path=str(private/'qualified-direct-login.png'),full_page=True)
 unassigned_context=browser.new_context();unassigned=login(unassigned_context,second)
 unassigned.wait_for_function("document.querySelector('#status').innerText.length>0")
 check('independent_session_has_no_implicit_study_rights',unassigned.locator('#study').input_value()=='' and unassigned.locator('#management-transition').count()==0)
 direct=browser.new_context(extra_http_headers={'X-Forwarded-User':creds['subject'],'X-Delphyr-Gateway':'browser-forgery'}).new_page()
 try:
  direct.goto('http://172.30.247.3:3860/',timeout=5000)
 except BrowserTimeout:
  check('direct_application_forgery_has_no_study_access',True)
 else:
  direct.wait_for_selector('#shiny-disconnected-overlay',state='attached',timeout=5000)
  check('direct_application_forgery_has_no_study_access',direct.locator('#study').input_value()=='')
 before=database()
 try:
  database(False)
  page.locator('#management-reason').fill('Synthetic principal-revocation qualification probe.')
  page.locator('#management-confirm').check();page.locator('#management-transition').click()
  page.wait_for_function("document.querySelector('#management-status').innerText.length>0")
  check('current_principal_revocation_blocks_existing_session_mutation',database()==before and 'fehlgeschlagen' in page.locator('#management-status').inner_text())
  denied=manager_context.new_page();denied.goto('http://127.0.0.1:4189/');denied.wait_for_selector('#shiny-disconnected-overlay',state='attached')
  check('disabled_principal_new_session_fails_closed',denied.locator('#study').input_value()=='')
 finally:database(True)
 browser.close()
evidence['passed']=all(evidence['checks'].values())
(private/'qualification.json').write_text(json.dumps(evidence,indent=2))
print(json.dumps({'passed':evidence['passed'],'checks':len(evidence['checks']),'backend':evidence['backend']}))
