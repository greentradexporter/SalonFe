# Admin login access repair

The published Pritze Control Center is:
https://pritze-control-center.greentradexporter.chatgpt.site/

The Site already permits public visits and protects its dashboard with the
existing assigned User ID/password flow. No Site audience change was needed.

The asia-south1 signInAdminWithPassword callable was blocked by an empty Cloud Run
IAM policy. Ordinary browser requests received Google's HTML HTTP 403 before the
application could validate the assigned credentials. This was not a password
reset problem.

Repair: on Cloud Run service signinadminwithpassword in project trimtime-46539,
restore roles/run.invoker for allUsers. This permits callers to reach the login
handler; the handler still validates passwords, active administrator records,
rate limits and lockouts. The function source already declares invoker: public,
so no source deployment was required. No passwords, administrator records, other
service policies, production business records or Site access settings were changed.

Verification:
- Before repair: unauthenticated empty login request returned HTML HTTP 403.
- After repair: the same request returned callable JSON INVALID_ARGUMENT HTTP 400,
  showing that application validation now handles the request.
- Existing User 1 credentials successfully opened the live dashboard in Chrome.
  The page displayed User 1 / Platform administrator and live operational metrics.
- getAdminPhaseOneData, getDiscountAdministrationDataAsAdmin and
  getProinPhaseOneDataAsAdmin all rejected signed-out requests with HTTP 401
  UNAUTHENTICATED; dashboard data was not made anonymous.
- Eight admin authentication/control-surface automated tests passed.

The shared login endpoint is used by every existing assigned admin account.
A person must still have a valid, active assigned User ID and its matching
password. No public administrator registration was introduced.

Cloud Run also reported older failed CPU-quota revision conditions. Live browser
sign-in and data loading succeeded after the IAM repair; no revision/CPU changes
were necessary for this repair.
