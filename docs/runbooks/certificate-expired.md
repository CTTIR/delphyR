# Certificate expired

TLS ends at the organisation's reverse proxy, in front of the authentication
gateway. The software holds no certificate; the local development setup uses
plain HTTP on the loopback interface only.

## Recognise

- Browsers warn or refuse the connection. Sign-in fails for everybody at once,
  including people who were signed in.
- The identity provider may refuse the redirect back to the application when
  the provider's or the application's certificate is invalid.
- The application and worker logs show nothing: the requests never arrive.

## First

1. Check the certificate of the public address and of the identity provider.
2. Do not ask anybody to accept a warning and continue. Do not switch the
   public address to plain HTTP.
3. Tell the study lead: participation is interrupted, saved responses are
   unaffected.

## Resume

1. Renew and install the certificate at the reverse proxy; reload it.
2. Sign in with a synthetic account from outside the internal network.
3. For a deadline that passed during the interruption see step 5 of
   [database outage](database-outage.md).
4. Add the expiry date to the organisation's monitoring; the software does not
   watch certificates.

## Responsible

Operator.

## Evidence

Expiry and renewal times, the monitoring entry created, and the decision about
deadlines.
