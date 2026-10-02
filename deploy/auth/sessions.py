#!/usr/bin/env python3
"""Session settings of the private local gateway fixture; print no secrets.

Usage: python3 deploy/auth/sessions.py

Brings an existing fixture up to date: signing out at the gateway also ends
the session at the identity provider. Writes proxy-lifetime.cfg, the same
gateway configuration with a session of 60 seconds, for compose.lifetime.yaml.
"""
from pathlib import Path
import os,re
private=Path(__file__).resolve().parents[2]/'.local/auth'
path=private/'proxy.cfg'
text=path.read_text()
logout='backend_logout_url = "http://keycloak:8080/realms/delphyr/protocol/openid-connect/logout?id_token_hint={id_token}"\n'
if 'backend_logout_url' not in text:
    text,n=re.subn(r'(redirect_url = "[^"\n]*"\n)',lambda m:m.group(1)+logout,text,count=1)
    if n!=1: raise SystemExit('Unexpected proxy.cfg; not changed.')
    path.write_text(text)
    print('Provider logout on gateway sign-out added to the private gateway configuration.')
short,n=re.subn(r'cookie_expire = "[^"\n]*"\n',lambda m:'cookie_expire = "60s"\n',text)
if n!=1: raise SystemExit('Unexpected proxy.cfg; lifetime configuration not written.')
target=private/'proxy-lifetime.cfg'
target.write_text(short);os.chmod(target,0o644)
print('Gateway configuration with a session of 60 seconds written for the lifetime check.')
