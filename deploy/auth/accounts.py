#!/usr/bin/env python3
"""Further synthetic accounts for the routing check; print no secrets.

Usage: python3 deploy/auth/accounts.py N   (1 to 24)

Adds accounts without any registration in the application to the private
realm fixture and records their credentials in routing-credentials.json.
Existing accounts keep their subjects and passwords. Recreate the identity
provider afterwards so that it imports the realm again, and restart the proxy.
"""
from pathlib import Path
import json,os,secrets,sys,uuid
count=int(sys.argv[1]) if len(sys.argv)==2 and sys.argv[1].isdigit() else 0
if not 1<=count<=24: raise SystemExit(__doc__)
private=Path(__file__).resolve().parents[2]/'.local/auth'
realm_path=private/'realm.json';target=private/'routing-credentials.json'
realm=json.loads(realm_path.read_text())
accounts=json.loads(target.read_text()) if target.exists() else []
known={user['username'] for user in realm['users']}
for number in range(len(accounts)+1,count+1):
    account={'username':f'synthetic-routing-{number}','password':secrets.token_urlsafe(20),'subject':str(uuid.uuid4())}
    accounts.append(account)
for account in accounts:
    if account['username'] in known: continue
    realm['users'].append({'id':account['subject'],'username':account['username'],
     'email':account['username']+'@example.invalid','emailVerified':True,'enabled':True,
     'firstName':'Synthetic','lastName':'Routing',
     'credentials':[{'type':'password','value':account['password'],'temporary':False}]})
realm_path.write_text(json.dumps(realm,indent=2));os.chmod(realm_path,0o644)
target.write_text(json.dumps(accounts));os.chmod(target,0o600)
print(f'{len(accounts)} routing account(s) in the private realm fixture; credentials were not printed.')
