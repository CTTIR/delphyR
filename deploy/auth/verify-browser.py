#!/usr/bin/env python3
"""Real local OIDC + direct Shiny qualification; never print credentials/cookies.

Usage:
  verify-browser.py              all checks of the running direct backend,
                                 with one or several application processes
  verify-browser.py --lifetime   session lifetime checks; start the gateway and
                                 the application with compose.lifetime.yaml first
"""
import json,subprocess,sys,time,zipfile
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright,TimeoutError as BrowserTimeout
root=Path(__file__).resolve().parents[2];private=root/'.local/auth'
creds=json.loads((private/'credentials.json').read_text())
second=json.loads((private/'second-credentials.json').read_text())
identity=json.loads((private/'identity.json').read_text())
lifetime_only='--lifetime' in sys.argv
origin='http://127.0.0.1:4189';provider='http://127.0.0.1:4190/realms/delphyr/protocol/openid-connect/auth'
started=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
evidence={'backend':'direct shiny::runApp; stock Shiny Server OSS remains unqualified','checks':{}}
def check(name,value):
 evidence['checks'][name]=bool(value)
 if not value: raise AssertionError(name)
def rscript(code):
 """Trusted fixture operations with the owner connection; prints nothing secret."""
 prelude='''.libPaths(c(normalizePath('.R-library'),.libPaths()));
 suppressMessages(pkgload::load_all('packages/delphyr',quiet=TRUE));options(delphyr.log_level='off');
 fixture<-jsonlite::fromJSON('.local/auth/identity.json');second<-jsonlite::fromJSON('.local/auth/second-credentials.json');
 r<-connect_repository(host='127.0.0.1',port=55439,dbname='delphyr',user='postgres',environment='test');
 issuer<-'http://127.0.0.1:4190/realms/delphyr';
 '''
 return subprocess.run(['Rscript','-e',prelude+code+';DBI::dbDisconnect(r$con)'],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
def rounds():
 return rscript("cat(query(r,'SELECT state FROM research.rounds WHERE study_id=$1 ORDER BY number',fixture$study_id)$state,sep=',')")
def running(name):
 return subprocess.run(['docker','inspect','-f','{{.State.Running}}',name],capture_output=True,text=True).stdout.strip()=='true'
containers=[c for c in ['delphyr-auth-app','delphyr-auth-app2','delphyr-auth-app3','delphyr-auth-app4'] if running(c)]
def entries(container):
 """Entries of the technical log of one application process since the start of this run."""
 out=subprocess.run(['docker','logs','--since',started,container],capture_output=True,text=True)
 found=[]
 for line in (out.stdout+out.stderr).splitlines():
  if line.startswith('{'):
   try: found.append(json.loads(line))
   except ValueError: pass
 return found
def process_of(operation):
 """The application process that served the most recent call of an operation."""
 latest=None
 for container in containers:
  for entry in entries(container):
   if entry.get('operation')==operation and (latest is None or entry.get('time','')>latest[0]): latest=(entry.get('time',''),container)
 return latest[1] if latest else None
def login(context,credential,path='/'):
 page=context.new_page();page.goto(origin+path,wait_until='networkidle')
 if page.locator('#username').count():
  page.locator('#username').fill(credential['username']);page.locator('#password').fill(credential['password'])
  page.locator('#kc-login').click()
 page.wait_for_selector('#banner');page.wait_for_timeout(1000)
 return page
def attempt_transition(page):
 page.locator('#management-reason').fill('Synthetic qualification probe.')
 if not page.locator('#management-confirm').is_checked(): page.locator('#management-confirm').check()
 page.locator('#management-transition').click()
 page.wait_for_function("document.querySelector('#management-status').innerText.includes('Reference:')")
 return page.locator('#management-status').inner_text()
def record(mode):
 evidence['passed']=all(evidence['checks'].values())
 evidence['commit']=subprocess.run(['git','rev-parse','HEAD'],cwd=root,capture_output=True,text=True).stdout.strip()
 # The image is built from the packages; documentation may differ from the commit.
 evidence['sources_match_commit']=subprocess.run(['git','status','--porcelain','--','packages','deploy','scripts',':(exclude)*.md'],cwd=root,capture_output=True,text=True).stdout.strip()==''
 evidence['executed_at']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
 path=private/'qualification.json'
 history=json.loads(path.read_text()) if path.exists() else {}
 runs=history.get('runs',{}) if isinstance(history.get('runs'),dict) else {}
 runs[mode]=evidence
 path.write_text(json.dumps({'runs':runs},indent=2))
 print(json.dumps({'mode':mode,'passed':evidence['passed'],'checks':len(evidence['checks']),'application_processes':len(containers),'backend':evidence['backend']}))

if lifetime_only:
 # compose.lifetime.yaml: the identity of an application session ends after
 # 20 seconds, the session of the gateway after 60.
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
  context=browser.new_context();page=login(context,creds);signed_in=time.time()
  page.wait_for_function("document.querySelector('#study').value !== ''")
  before=rounds();page.wait_for_timeout(25000)
  text=attempt_transition(page)
  check('expired_session_identity_blocks_action_in_open_websocket',rounds()==before and text.startswith('Your sign-in has expired.'))
  visited=[];again=context.new_page();again.on('request',lambda request:visited.append(request.url))
  again.goto(origin+'/',wait_until='networkidle');again.wait_for_selector('#banner')
  again.wait_for_function("document.querySelector('#study').value !== ''")
  check('page_load_within_the_gateway_session_resolves_the_identity_again',again.locator('#study').input_value()==identity['study_id'] and not any(url.startswith(provider) for url in visited))
  again.wait_for_timeout(max(0,int((signed_in+66-time.time())*1000)))
  visited.clear();later=context.new_page();later.on('request',lambda request:visited.append(request.url))
  later.goto(origin+'/',wait_until='networkidle')
  check('expired_gateway_session_is_not_accepted',any(url.startswith(provider) for url in visited))
  later.wait_for_selector('#banner');later.wait_for_function("document.querySelector('#study').value !== ''")
  check('provider_session_renews_the_sign_in_without_credentials',later.locator('#username').count()==0 and later.locator('#study').input_value()==identity['study_id'])
  browser.close()
 evidence['identity_lifetime_seconds']=20;evidence['gateway_session_seconds']=60
 record('lifetime');sys.exit(0)

http=requests.Session();http.trust_env=False
response=http.get(origin+'/',allow_redirects=False,timeout=5)
check('unauthenticated_redirect',response.status_code==302)
response=http.get(origin+'/',headers={'X-Forwarded-User':creds['subject'],'X-Delphyr-Gateway':'forged'},allow_redirects=False,timeout=5)
check('unauthenticated_forged_headers_rejected',response.status_code==302)
response=http.get(origin+'/',headers={'Cookie':'_oauth2_proxy=forged'},allow_redirects=False,timeout=5)
check('forged_cookie_rejected',response.status_code==302)
response=http.get(origin+'/oauth2/callback?code=forged&state=forged',allow_redirects=False,timeout=5)
check('callback_without_valid_csrf_rejected',response.status_code in (400,403,500))
try:
 response=http.get('http://172.30.246.3:8080/',timeout=3)
 check('direct_internal_gateway_rejected',response.status_code==403)
except requests.RequestException: check('direct_internal_gateway_rejected',True)
inspected=[json.loads(subprocess.run(['docker','inspect',c],check=True,capture_output=True,text=True).stdout)[0] for c in containers]
check('application_has_no_published_port',len(containers)>=1 and not any(c['HostConfig'].get('PortBindings') for c in inspected))
addresses=[c['NetworkSettings']['Networks']['delphyr-auth-back']['IPAddress'] for c in inspected]

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
 refused=[]
 for address in addresses:
  direct=browser.new_context(extra_http_headers={'X-Forwarded-User':creds['subject'],'X-Delphyr-Gateway':'browser-forgery'}).new_page()
  try:
   direct.goto('http://%s:3860/'%address,timeout=5000)
  except BrowserTimeout:
   refused.append(True)
  else:
   direct.wait_for_selector('#shiny-disconnected-overlay',state='attached',timeout=5000)
   refused.append(direct.locator('#study').input_value()=='')
 check('direct_application_forgery_has_no_study_access',len(refused)==len(containers) and all(refused))

 # A request with a body carries the session's own address: it reaches the
 # process that holds the session, also with several application processes.
 upload=private/'qualification-panel.csv'
 upload.write_text('external_ref,email,display_name,locale,stakeholder_group\nQ-%d,qualification-%d@example.invalid,Synthetic Contact,en,professionals\n'%(int(time.time()),int(time.time())))
 try:
  page.set_input_files('#panel_import-file',str(upload))
  page.wait_for_function("(function(){var x=document.querySelector('#panel_import-file_progress .progress-bar');return !!x && x.innerText.toLowerCase().includes('complete');})()")
  page.locator('#panel_import-preview').click()
  page.wait_for_function("document.querySelector('#panel_import-status').innerText.length>0")
  check('upload_reaches_the_process_of_its_session','Preview passed validation.' in page.locator('#panel_import-status').inner_text())
 finally:
  upload.unlink()

 # An export is built by a worker in another process and downloaded through
 # the session's process: the private export directory is shared storage.
 page.wait_for_function("(function(){var x=document.getElementById('exports-profile');return !!x && !!x.selectize && Object.keys(x.selectize.options).includes('audit_restricted');})()")
 page.evaluate("document.getElementById('exports-profile').selectize.setValue('audit_restricted')")
 page.wait_for_timeout(500)
 if not page.locator('#exports-confirm').is_checked(): page.locator('#exports-confirm').check()
 page.wait_for_timeout(300);page.locator('#exports-request').click()
 page.wait_for_function("document.querySelector('#exports-status').innerText.includes('Export queued.')")
 serving=process_of('request_study_export')
 others=[c for c in containers if c!=serving]
 worker=others[0] if others else containers[0]
 subprocess.run(['docker','exec','-u','shiny',worker,'Rscript','-e',
  "r<-delphyr::connect_repository(host='delphyr-auth-db',port=5432,dbname='delphyr',user='delphyr_runtime',environment='development',artifact_root='/var/lib/delphyr-artifacts');"
  "while(!identical(delphyr::worker_step(r,study_id='%s'),FALSE)) NULL"%identity['study_id']],check=True,capture_output=True,text=True)
 page.locator('#exports-poll').click()
 page.wait_for_function("document.querySelector('#exports-status').innerText.includes('Succeeded')")
 page.wait_for_function("(function(){var a=document.getElementById('exports-download');return !!a && !!a.getAttribute('href');})()")
 with page.expect_download() as download:
  page.locator('#exports-download').click()
 names=zipfile.ZipFile(download.value.path()).namelist()
 check('export_download_reaches_the_process_of_its_session','audit_events.csv' in names and 'manifest.json' in names)
 evidence['export']={'session_process':serving,'worker_process':worker,'shared_storage_exercised':serving is not None and worker!=serving}

 # A right revoked while the session is open: the next protected action is refused.
 capability="UPDATE identity.capabilities c SET revoked_at=%s FROM identity.memberships m WHERE m.study_id=c.study_id AND m.id=c.membership_id AND c.study_id=$1 AND m.principal_id=$2 AND c.capability=$3"
 before=rounds()
 try:
  rscript("invisible(execute(r,'%s',fixture$study_id,fixture$principal_id,'manage'))"%(capability%'clock_timestamp()'))
  text=attempt_transition(page)
  check('revoked_right_blocks_action_in_open_websocket',rounds()==before and text.startswith('Action failed'))
 finally:
  rscript("invisible(execute(r,'%s',fixture$study_id,fixture$principal_id,'manage'))"%(capability%'NULL'))

 # An invitation is bound to the invited account and needs a confirmed action.
 invitation=json.loads(rscript('''f<-demo_study(r,n=2L,item_count=2L);
  csv<-paste('external_ref,email,display_name,locale,stakeholder_group',paste0('G-1,gateway-',substr(uid(),1,8),'@example.invalid,Synthetic Invitee,en,professionals'),sep='\\n');
  p<-preview_panel_import(r,f$manager,f$study_id,csv);draft<-import_panel(r,f$manager,f$study_id,p,p$hash,'Synthetic contact','import')$invitation_ids[[1]];
  account<-register_invited_account(r,f$manager,f$study_id,issuer,second$subject,'Stable account of the invited person','register')$id;
  token<-new_invitation_token();inv<-issue_panel_invitation(r,f$manager,f$study_id,draft,account,token,900L,'Approved account','issue')$id;
  cat(jsonlite::toJSON(list(study=f$study_id,account=account,code=as.character(invitation_code(f$study_id,inv,token))),auto_unbox=TRUE))'''))
 members=lambda: rscript("cat(query(r,'SELECT count(*)::int AS n FROM identity.memberships WHERE study_id=$1 AND principal_id=$2 AND active','%s','%s')$n)"%(invitation['study'],invitation['account']))
 link=origin+'/#invitation='+invitation['code']
 try:
  # A scanner without a session is sent to the sign-in; the code is never part of a request.
  response=http.get(link,allow_redirects=False,timeout=5)
  check('unauthenticated_visit_of_the_link_accepts_nothing',response.status_code==302 and members()=='0')
  # The manager's account cannot use a code issued for another account.
  other=manager_context.new_page();other.goto(link,wait_until='networkidle')
  other.wait_for_selector('#invitation_accept-check');other.wait_for_function("document.querySelector('#invitation_accept-code').value.length>0")
  other.locator('#invitation_accept-check').click()
  other.wait_for_function("document.querySelector('#invitation_accept-status').innerText.includes('Reference:')")
  check('invitation_of_another_account_refused',members()=='0' and other.locator('#invitation_accept-accept').count()==0 and 'not available for your account' in other.locator('#invitation_accept-status').inner_text())
  other.close()
  invitee=unassigned_context.new_page();invitee.goto(link,wait_until='networkidle')
  invitee.wait_for_selector('#invitation_accept-check');invitee.wait_for_function("document.querySelector('#invitation_accept-code').value.length>0")
  check('opening_the_link_signed_in_accepts_nothing',members()=='0')
  invitee.locator('#invitation_accept-check').click();invitee.wait_for_selector('#invitation_accept-accept')
  check('preview_before_confirmation_accepts_nothing',members()=='0')
  invitee.locator('#invitation_accept-confirm').check();invitee.locator('#invitation_accept-accept').click()
  invitee.wait_for_function("document.querySelector('#invitation_accept-preview').innerText.includes('Invitation accepted.')")
  check('invitation_accepted_by_the_invited_account',members()=='1')
  invitee.wait_for_function("document.querySelector('#study').value==='%s'"%invitation['study'])
  invitee.wait_for_selector('#panel-load')
  check('accepted_member_has_participation_only',invitee.locator('#management-transition').count()==0 and invitee.locator('#panel-load').count()==1)
  invitee.close()
 finally:
  rscript("invisible(execute(r,'UPDATE identity.memberships SET active=false WHERE study_id=$1 AND principal_id=$2','%s','%s'))"%(invitation['study'],invitation['account']))
 lost=unassigned_context.new_page();lost.goto(origin+'/',wait_until='networkidle');lost.wait_for_selector('#banner')
 lost.wait_for_function("document.querySelector('#status').innerText.length>0")
 check('deactivated_membership_removes_access',lost.locator('#study').input_value()=='')

 before=rounds()
 try:
  rscript("invisible(execute(r,'UPDATE identity.principals SET active=false WHERE id=$1',fixture$principal_id))")
  text=attempt_transition(page)
  check('current_principal_revocation_blocks_existing_session_mutation',rounds()==before and text.startswith('Action failed'))
  denied=manager_context.new_page();denied.goto(origin+'/');denied.wait_for_selector('#shiny-disconnected-overlay',state='attached')
  check('disabled_principal_new_session_fails_closed',denied.locator('#study').input_value()=='')
  check('unregistered_notice_shown_for_the_closed_session',denied.locator('#unregistered').is_visible())
  denied.close()
 finally:rscript("invisible(execute(r,'UPDATE identity.principals SET active=true WHERE id=$1',fixture$principal_id))")

 # Accounts unknown to the application are refused by whichever process the
 # gateway chose for them, which the technical log of that process records:
 # different accounts are spread over the processes and one account always
 # reaches the same process.
 routing=private/'routing-credentials.json'
 if routing.exists() and len(containers)>1:
  def refusals(): return {c:sum(1 for e in entries(c) if e.get('operation')=='session_identity' and e.get('error_path')=='authentication.principal') for c in containers}
  def visit(context,credential):
   seen=refusals();probe=context.new_page();probe.goto(origin+'/',wait_until='networkidle')
   if probe.locator('#username').count():
    probe.locator('#username').fill(credential['username']);probe.locator('#password').fill(credential['password'])
    probe.locator('#kc-login').click()
   probe.wait_for_selector('#unregistered',state='visible');probe.close()
   for attempt in range(50):
    now=refusals();reached=[c for c in containers if now[c]>seen[c]]
    if reached: return reached
    time.sleep(0.1)
   return []
  first=[];second_visit=[]
  for credential in json.loads(routing.read_text()):
   context=browser.new_context()
   first.append(visit(context,credential));second_visit.append(visit(context,credential));context.close()
  check('each_account_reaches_exactly_one_process',all(len(x)==1 for x in first+second_visit))
  check('second_visit_of_an_account_reaches_the_same_process',first==second_visit)
  spread={c:sum(1 for x in first if x==[c]) for c in containers}
  check('accounts_are_spread_over_the_processes',sum(1 for n in spread.values() if n>0)>=2)
  evidence['routing']={'accounts':len(first),'accounts_by_process':spread}

 # Sessions of this run by application process, from the technical log at level info.
 evidence['sessions_by_process']={c:sum(1 for e in entries(c) if e.get('operation')=='session_identity' and e.get('outcome')=='ok') for c in containers}

 # Signing out: the link leaves the application and ends the account's other
 # open page; the gateway drops its session and ends the session at the provider.
 page.goto(origin+'/',wait_until='networkidle');page.wait_for_function("document.querySelector('#study').value !== ''")
 fresh=manager_context.new_page();fresh.goto(origin+'/',wait_until='networkidle');fresh.wait_for_selector('#sign_out')
 check('other_page_of_the_account_is_connected_before_sign_out',page.locator('#shiny-disconnected-overlay').count()==0)
 fresh.locator('#sign_out').click();fresh.wait_for_selector('#username')
 check('sign_out_leaves_the_application_and_ends_the_gateway_session',not any(x['name'].startswith('_oauth2_proxy') and x['value'] and not x['name'].endswith('_csrf') for x in manager_context.cookies()))
 page.wait_for_selector('#shiny-disconnected-overlay',state='attached')
 check('sign_out_ends_the_other_open_page_of_the_account',page.locator('#shiny-disconnected-overlay').count()==1)
 again=manager_context.new_page();again.goto(origin+'/',wait_until='networkidle')
 check('visit_after_sign_out_requires_credentials',again.locator('#username').count()==1 and again.locator('#study').count()==0)
 browser.close()
evidence['application_processes']=len(containers)
record('processes-%d'%len(containers))
