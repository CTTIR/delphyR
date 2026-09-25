#!/usr/bin/env python3
"""Generate private synthetic OIDC credentials; print no secrets."""
from pathlib import Path
import base64,json,os,secrets,uuid
root=Path(__file__).resolve().parents[2]
private=root/'.local/auth'
private.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(private,0o700)
if (private/'realm.json').exists():
    raise SystemExit('Existing auth fixture preserved. Reuse it; do not overwrite an active realm.')
client=secrets.token_urlsafe(32);gateway=secrets.token_hex(32)
password=secrets.token_urlsafe(20)
subject=str(uuid.uuid4())
second={'username':'synthetic-no-study','password':secrets.token_urlsafe(20),'subject':str(uuid.uuid4())}
realm={'realm':'delphyr','enabled':True,'registrationAllowed':False,'resetPasswordAllowed':False,
 'sslRequired':'none','accessTokenLifespan':900,'ssoSessionIdleTimeout':900,'ssoSessionMaxLifespan':1800,
 'clients':[{'clientId':'delphyr-local','enabled':True,'protocol':'openid-connect','publicClient':False,
 'secret':client,'standardFlowEnabled':True,'directAccessGrantsEnabled':False,
 'redirectUris':['http://127.0.0.1:4189/oauth2/callback'],'webOrigins':['http://127.0.0.1:4189'],
 'attributes':{'pkce.code.challenge.method':'S256'},'defaultClientScopes':['profile','email']}],
 'users':[{'id':subject,'username':'synthetic-manager','email':'synthetic-manager@example.invalid',
 'emailVerified':True,'enabled':True,'firstName':'Synthetic','lastName':'Manager',
 'credentials':[{'type':'password','value':password,'temporary':False}]}]}
realm['users'].append({'id':second['subject'],'username':second['username'],
 'email':'synthetic-no-study@example.invalid','emailVerified':True,'enabled':True,
 'firstName':'Synthetic','lastName':'Unassigned',
 'credentials':[{'type':'password','value':second['password'],'temporary':False}]})
proxy=f'''http_address = "0.0.0.0:4180"
provider = "oidc"
provider_display_name = "Synthetic local Keycloak"
oidc_issuer_url = "http://127.0.0.1:4190/realms/delphyr"
skip_oidc_discovery = true
login_url = "http://127.0.0.1:4190/realms/delphyr/protocol/openid-connect/auth"
redeem_url = "http://keycloak:8080/realms/delphyr/protocol/openid-connect/token"
oidc_jwks_url = "http://keycloak:8080/realms/delphyr/protocol/openid-connect/certs"
profile_url = "http://keycloak:8080/realms/delphyr/protocol/openid-connect/userinfo"
redirect_url = "http://127.0.0.1:4189/oauth2/callback"
client_id = "delphyr-local"
client_secret = "{client}"
cookie_secret = "{base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()}"
cookie_secure = false
cookie_httponly = true
cookie_samesite = "lax"
cookie_expire = "15m"
cookie_refresh = "0"
code_challenge_method = "S256"
insecure_oidc_skip_nonce = false
insecure_oidc_skip_issuer_verification = false
email_domains = ["example.invalid"]
scope = "openid profile email"
upstreams = ["http://gateway:8080/"]
reverse_proxy = false
skip_auth_strip_headers = true
pass_user_headers = true
prefer_email_to_user = false
pass_basic_auth = false
pass_access_token = false
pass_authorization_header = false
skip_provider_button = true
request_logging = false
auth_logging = false
show_debug_on_error = false
'''
nginx=f'''events {{}}
http {{
  access_log off;
  map $http_upgrade $connection_upgrade {{ default upgrade; '' close; }}
  server {{
    listen 8080;
    allow 172.30.246.2;
    deny all;
    location / {{
      proxy_pass http://app:3860;
      proxy_http_version 1.1;
      proxy_set_header Host $http_host;
      proxy_set_header X-Forwarded-User $http_x_forwarded_user;
      proxy_set_header X-Delphyr-Gateway "{gateway}";
      proxy_set_header Authorization "";
      proxy_set_header X-Forwarded-Access-Token "";
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_read_timeout 20m;
    }}
  }}
}}
'''
files={'realm.json':json.dumps(realm,indent=2),'proxy.cfg':proxy,'nginx.conf':nginx,
 'gateway.secret':gateway,'credentials.json':json.dumps({'username':'synthetic-manager','password':password,'subject':subject}),
 'second-credentials.json':json.dumps(second)}
for name,value in files.items():
 p=private/name;p.write_text(value);os.chmod(p,0o600)
# Container daemons need to read these specific files; parent directory stays0700.
for name in ['realm.json','proxy.cfg','nginx.conf','gateway.secret']:
 os.chmod(private/name,0o644)
print('Private synthetic auth fixture prepared in .local/auth; credentials were not printed.')
