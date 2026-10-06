# Account email delivery

2026-10-06 follow-up on `integration/wady-ezz`. This changes only account email
reliability and registration notices; prayer inference/scoring and identity,
guardian, child, family and mosque authorization remain unchanged.

## Flow and guarantees

Signup/resend/recovery writes the account/profile where needed, hashed expiring
token and private mail intent in one transaction. The transaction commits **before**
SMTP/Resend is contacted. A failed commit cannot send a message. A lost provider
acknowledgement or DB acknowledgement leaves a durable retryable job and valid token.

The API attempts immediate submission outside the DB lock. On transport failure
signup still saves the unverified account and returns `delivery=queued`,
`submission=queued`, with a safe `delivery_error` code. Flutter displays pending
delivery and does not sign in automatically. Successful provider acceptance returns
`submission=accepted`; development mode returns `delivery=development_outbox`,
`submission=stored` and explicitly says no external mail was sent.

The backend lifespan starts a worker, polling every two seconds. Jobs use a
120-second lease across API calls/workers, retry after 30 seconds with exponential
backoff capped at 300 seconds, and stop when the original 30-minute token expires
or is consumed/replaced. Restart recovers committed jobs and expired leases.
Repeated pending signup requests reuse the same token and intent. A definitely
rejected job can be replaced after changing sender/public URL/provider settings;
ambiguous timeouts retain the original envelope and idempotency key.

Resend retries use the same token-derived `Idempotency-Key` and frozen sender,
recipient, subject and link. SMTP uses a stable Message-ID; SMTP cannot guarantee
exactly-once delivery after an ambiguous acknowledgement. A duplicate message uses
the same valid one-use link. A crashed lease can delay the next attempt by up to
120 seconds. Expired links require an explicit new verification/recovery request.

Recovery/resend response messages remain conditional on the email being registered;
they do not expose per-account provider errors or receipt status. Receiving a mail
delivery event **never** verifies the account: consuming the verification link is
still required.

## Storage and migration

Additive schema **4** adds `account_email_outbox` and `account_email_events`. Existing
accounts, profiles, sessions, prayer attempts, scores and schema-v3 fields survive.
No reset, deletion or migration rewrite is required.

Pending private payloads contain the raw verification link required to retry. They
must be protected with the account DB and backups. Payloads are cleared after
acceptance, expiry or supersession. Credentials are read from backend settings;
they are never persisted in mail jobs. APIs and logs do not return raw link tokens.
Development `.eml` files contain links and remain private operator test artifacts.

An operator can inspect status without exposing payloads:

```sql
SELECT id, kind, mode, state, attempts, error_code,
       datetime(next_attempt_at,'unixepoch') AS next_attempt_utc,
       provider_id, delivery_status
FROM account_email_outbox ORDER BY created_at DESC;
```

`ACCEPTED` means the provider accepted submission. `delivery_status=UNKNOWN` remains
until an authenticated receipt reports delivery, delay, bounce, failure, suppression
or complaint. SMTP has no built-in delivery receipt integration.

## Configuration

Use backend environment settings; never commit secrets:

- `ACCOUNT_PUBLIC_URL`: externally accessible HTTPS backend containing `/api/`.
- `ACCOUNT_MAIL_WORKER_ENABLED=true`: automatic retry, enabled by default.
- Resend: `ACCOUNT_MAIL_MODE=resend`, `ACCOUNT_RESEND_API_KEY`,
  `ACCOUNT_MAIL_FROM` on a verified domain.
- SMTP: `ACCOUNT_MAIL_MODE=smtp`, host/port/user/password. Set
  `ACCOUNT_SMTP_SECURITY=auto` (default): SSL from connection start on port 465,
  otherwise STARTTLS. Explicit `ssl` / `starttls` override auto selection.
  Both verify TLS certificates. There is no plaintext fallback.
- Development: `ACCOUNT_MAIL_MODE=development`, private `ACCOUNT_MAIL_OUTBOX`.
  This never verifies accounts automatically or sends external messages.

For Resend delivery tracking, configure an HTTPS webhook in the Resend dashboard:

```text
POST https://YOUR_BACKEND/api/v1/accounts/auth/mail-events
ACCOUNT_RESEND_WEBHOOK_SECRET=whsec_...  (backend secret only)
```

Subscribe to `email.delivered`, `email.bounced`, `email.failed`,
`email.delivery_delayed`, `email.suppressed` and `email.complained`.
The endpoint checks Svix v1 HMAC on raw request bytes and a five-minute timestamp
window. It requires no guardian cookie or `X-Iqtadi-Account` header. Missing secret,
invalid signature/timestamp, malformed payloads and oversized bodies are rejected.
Receipts are deduplicated by event ID; out-of-order receipts cannot overwrite newer
status. Receipts arriving before the send acknowledgement are saved and reconciled
once the provider email ID is known. Receipt states stay private to the backend.

References: [Resend sending](https://resend.com/docs/api-reference/emails/send-email),
[Resend receipt events](https://resend.com/docs/webhooks/event-types),
[Svix signature specification](https://docs.svix.com/receiving/verifying-payloads/how-manual),
[Python SMTP TLS](https://docs.python.org/3/library/smtplib.html).

## Verification and limits

| Check | Result | Evidence |
| --- | --- | --- |
| Final account, family/mosque and semantic API suites | PASS | 62 passed in 308.77s; includes all 16 new mail tests. `output/mail-accounts-final.log`. |
| Complete backend suite | FAIL | 198 passed, the same four inherited prayer boundary cases failed. Run preceded the last two mail configuration/DB-ack tests; final account suite covers those changes. `output/mail-full-backend-tests.log`. |
| Flutter complete tests | PASS | 153 passed, including two new queued/accepted registration UI tests. `output/mail-full-flutter-tests.log`. |
| Flutter analyzer | FAIL for zero-diagnostic gate | Zero errors/warnings, six inherited infos, exit 1. `output/mail-flutter-analyze.log`. |
| Flutter Web release / offline manifest | PASS | 78 assets, 126,838,192 bytes. `output/mail-web-build.log`. |
| Android debug APK | PASS | Built with `flutter build apk --debug --no-pub`. `output/mail-android-build.log`. |
| Migration / model preservation | PASS | Wady, Ezz and prior integration schema upgraded to v4 twice without changing fixture rows/sessions; foreign keys clean. All 141 protected blobs and manifest hashes retained; packaged Web/APK model hashes match. `output/mail-migration-audit.json`, `output/mail-protection-audit.json`. |
| New mail module/tests Ruff and module mypy | PASS | Full-project checks still report 212 inherited Ruff diagnostics and five inherited mypy errors. |
| Chrome signup, verification, login/reload | PASS, development delivery | Real Flutter and verification page; injected outage followed by automatic worker retry. `output/mail-acceptance/browser-result.json`. |
| Real SMTP/Resend delivery and live webhook | NOT RUN | No sender/provider credentials configured locally or on the published VPS. Connected Gmail access is confirmed; actual mail/link test awaits provider setup. |

- Mail tests cover commit ordering/rollback, restart and lease recovery, concurrent
  dispatch, lost provider/DB acknowledgements, frozen retry envelopes, fixed sender
  settings, expiry/supersession, SMTP TLS/SSL and rejection, signed/tampered/stale
  receipts, receipt ordering and the published Svix signature reference vector.
- Browser acceptance creates an account through real Flutter during an injected
  mail outage, rejects unverified login, observes automatic retry to a private local
  `.eml`, opens the real verification page, logs in and reloads the cookie session.
  Screenshots and results: `output/mail-acceptance/`.
- External SMTP/Resend delivery, production DNS/domain verification and a configured
  live Resend webhook were **not** exercised. All transport tests are controlled;
  the browser host uses explicitly labelled development mail.
- The main gate remains closed for the four inherited prayer boundary failures,
  212 inherited Ruff diagnostics and five inherited mypy errors. This repair does
  not change protected prayer rules to force those checks to pass.
