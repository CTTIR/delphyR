#!/usr/bin/env python3
"""Route the local gateway to N application processes; print no secrets.

Usage: python3 deploy/auth/scale.py N   (1 to 4)

Rewrites only the upstream of the private nginx.conf. Start the additional
processes with compose.scale.yaml and reload the gateway afterwards.
"""
from pathlib import Path
import re,sys
count=int(sys.argv[1]) if len(sys.argv)==2 and sys.argv[1].isdigit() else 0
if not 1<=count<=4: raise SystemExit(__doc__)
path=Path(__file__).resolve().parents[2]/'.local/auth/nginx.conf'
text=path.read_text()
hosts=[3]+[10+i for i in range(2,count+1)]
servers=''.join(f'    server 172.30.247.{host}:3860;\n' for host in hosts)
upstream='  upstream delphyr_app {\n    hash $http_x_forwarded_user consistent;\n'+servers+'  }\n'
if 'upstream delphyr_app' in text:
    text,n=re.subn(r'  upstream delphyr_app \{.*?\n  \}\n',lambda m:upstream,text,flags=re.S)
else:
    # A fixture prepared before the upstream existed.
    text,n=re.subn(r'(\n  server \{)',lambda m:'\n'+upstream.rstrip('\n')+m.group(1),text,count=1)
    text=text.replace('proxy_pass http://app:3860;','proxy_pass http://delphyr_app;')
if n!=1 or 'proxy_pass http://delphyr_app;' not in text: raise SystemExit('Unexpected nginx.conf; not changed.')
path.write_text(text)
print(f'Gateway upstream set to {count} application process(es).')
