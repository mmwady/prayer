# Rich Ezz samples on the existing website

On 2026-10-06 the user explicitly chose **add samples to the current website
database while preserving my account**, rather than a separate demo environment.
This is an additive data operation, not replacement of the live SQLite file.

Website: https://vps-c79afd97.vps.ovh.ca

## Current data

The import preserved both pre-existing accounts, their profiles, family, sessions,
devices, verification tokens and accepted mail records. Within the import transaction,
every pre-existing row was checked unchanged. The schema remains v4; no migration,
application-image change or database reset was required.

| Added sample data | Count |
| --- | ---: |
| Verified accounts | 6 |
| Personal profiles / dependent children | 6 / 3 |
| Families | 2 |
| Mosque / staff roles | 1 / 2 |
| Mosque groups | 4 |
| Memberships / active consents | 5 / 5 |
| Synthetic practice summaries | 189 |
| Attendance events | 65 |
| Attendance sessions | 80 |
| Platform administrators | 1 |

Accounts are `demo@example.com` (father, family owner, mosque leader),
`guardian@example.com` (guardian), `newmuslim@example.com` (adult learner),
`elder@example.com` (large text, supporter), `sheikh@example.com` (mosque admin,
without guardianship) and `admin@example.com` (platform admin).

These are explicitly artificial samples: names/spaces carry `تجريبي`, and practice
records carry `demo-camera-local-v1`. They are not actual performed prayers.
The original nullable movement-coverage fields remain null; no scores were invented
to populate fields absent from the Ezz seed. No email was sent by seeding.

Private passwords replaced the documented local default. The platform-admin password
is separate. Invitation/check-in codes and token hashes were also replaced. Credentials
are only in the operator's ignored `output/server-rich-demo/credentials.private.json`;
no password, token, database or private credential file is committed to GitHub.

## Sample relationship corrections

The original Ezz seed placed children aged 8 and 15 in the 10–13 mosque group.
The importer creates separate 5–9 and 14–17 groups, moves their memberships and
consents, and re-associates attendance with cloned sessions. It copies the complete
schedule, including missed sessions, to preserve attendance denominators and rates.
All 189 practices and 65 attendance events survive. Live Ezz age/consent validation
is unchanged. Historical clones cannot be used as check-in codes.

The initial private-code preparation used mixed-case URL-safe strings. Those two
sample code hashes were corrected to Ezz's uppercase/space/hyphen normalization
inside a second backed-up transaction. All other rows were checked unchanged.
The reusable preparation tool generates compatible uppercase codes from the start.
An additional audit marker records the corrected source fingerprint; the original
import audit remains intact.

## Repeatable, controlled operation

Run from `backend/`, using a private ignored directory. Do not send account databases
from a developer machine: generate clean samples instead. The original Ezz seed and
upgrade scripts keep their isolated-demo behavior and guards.

```bash
python -m tools.prepare_account_demo_import \
  --db ../output/server-rich-demo/new.demo.sqlite3 \
  --credentials ../output/server-rich-demo/new.credentials.private.json

python -m tools.import_account_demo \
  --source ../output/server-rich-demo/new.demo.sqlite3 \
  --target data/iqtadi.accounts.sqlite3

# Only after successful dry-run and explicit authorization to add samples:
python -m tools.import_account_demo \
  --source ../output/server-rich-demo/new.demo.sqlite3 \
  --target data/iqtadi.accounts.sqlite3 \
  --apply --backup /private/backups/accounts.before.sqlite3
```

Use the actual configured `ACCOUNT_DB` as target; the path above is illustrative.
The live Docker image does not include operator tools: stage the importer and clean
source privately and execute with the existing Python runtime/configuration. Never
upload the credential JSON or the local application's real database.

The importer requires compatible existing schema v4, a valid source with exactly the
six Ezz sample accounts, no source auth sessions/devices/email payloads, private
replacement passwords/codes and the complete sample history. Dry-run inserts inside
a transaction and rolls it back. Apply uses SQLite's consistent backup API first,
then one transaction of INSERTs. A unique collision aborts everything; there is no
replace, reset or silent conflict skip. Repeating the same source returns
`ALREADY_IMPORTED`; a different source colliding with installed samples is rejected.

## Server backup and acceptance

Private server snapshots, root-owned with directory mode 0700 and file mode 0600:

- `/srv/iqtadi/backups/demo-20261006071619/accounts.before.sqlite3`
- `/srv/iqtadi/backups/demo-20261006071619/accounts.codes-before.sqlite3`

Never restore an old whole snapshot over newer user activity without reviewing the
data changes since that snapshot. No automatic destructive rollback was performed.

| Verification | Result |
| --- | --- |
| Final preparation/import tests (default code/password refusal, late collision rollback, real row/session preservation, backup, repeat import, age/consent/role contracts) | PASS — 12 |
| Existing account/space/mail tests | PASS — 60 (combined run passed 69 before the last preparation cases; final importer/preparer suite rerun separately) |
| Ruff on the two tools and new test file | PASS |
| Mypy on the two tools, imported dependencies skipped | PASS |
| Live dry-run / atomic import / foreign keys / retained real account | PASS |
| Live repeat import after code correction | PASS — no duplicate data |
| Real Chrome Flutter login and family/mosque screens | PASS |
| All six real HTTPS logins, preferences and platform/guardian/mosque isolation | PASS |
| Family ranking / four mosque practice and attendance boards / alias privacy / preserved attendance denominators | PASS |
| Private invitation/check-in resolution through the existing API | PASS — age/consent rejection proves resolution without changing memberships/events |
| Service health after the operation | PASS — healthy |

Browser evidence and sanitized operation results are in ignored
`output/server-rich-demo/`. No Flutter, prayer pipeline/model assets, auth runtime,
database schema or Web/mobile build configuration changed; these were not rebuilt
for this data-only operation. Physical QR scanning, a successful new child join or
new attendance event were not exercised in this operation. The sample check-in code
expires after 24 hours and the invitation after 30 days; leaders can issue fresh
codes using the existing UI. Existing inherited integration/main gates remain closed.
