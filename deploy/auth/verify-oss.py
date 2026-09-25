#!/usr/bin/env python3
"""Record the stock OSS header-transport rejection, not a successful auth claim."""
import json,subprocess
from pathlib import Path
from playwright.sync_api import sync_playwright
private=Path(__file__).resolve().parents[2]/'.local/auth'
c=json.loads((private/'credentials.json').read_text())
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 page=b.new_page();page.goto('http://127.0.0.1:4189/',wait_until='networkidle')
 page.locator('#username').fill(c['username']);page.locator('#password').fill(c['password']);page.locator('#kc-login').click()
 page.wait_for_url('http://127.0.0.1:4189/');page.wait_for_function("document.body.innerText.includes('Disconnected from the server.')")
 cookie=any(x['name']=='_oauth2_proxy' for x in page.context.cookies())
 denied=page.locator('#study').input_value()==''
 page.screenshot(path=str(private/'stock-oss-negative.png'),full_page=True)
 b.close()
logs=subprocess.run(['docker','logs','--tail','80','delphyr-auth-app'],capture_output=True,text=True,check=True)
worker_logs=subprocess.run(['docker','exec','delphyr-auth-app','sh','-c','cat /var/log/shiny-server/*.log 2>/dev/null'],capture_output=True,text=True)
missing='subject header present: FALSE; gateway header present: FALSE' in logs.stdout+logs.stderr+worker_logs.stdout
result={'backend':'stock Shiny Server OSS 1.5.24.1038','oidc_gateway_cookie_issued':cookie,
 'shiny_session_denied':denied,'custom_headers_missing_in_actual_session':missing,
 'qualified':False,'reason':'OSS websocket proxy discards trusted custom headers'}
print(json.dumps(result))
assert cookie and denied and missing
(private/'oss-negative.json').write_text(json.dumps(result,indent=2))
print(json.dumps({'negative_boundary_test_passed':True,'qualified':False}))
