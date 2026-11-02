# Content infrastructure

How chart content (songs, steps, patterns, jackets) reaches installed apps
without a store release, and how to rebuild, change or recover the infra
behind it. App-side behaviour is in [AGENTS.md](../AGENTS.md) (data flow §6).

```
DDR-BPM-prep ──copy──▶ ddr-md-content (private repo)
                          │ push to master (or staging) / daily 03:17 UTC / manual
                          ▼
            .github/workflows/publish.yml   (written by Terraform)
                          │ calls
                          ▼
   ddr-md/.github/workflows/publish-content.yml @ workflow_ref
     generate songlist + patterns → content_manifest → wrangler deploy
                          │ only when something changed
                          ▼
         Cloudflare Pages: ddr-md-content.pages.dev
                   (staging branch → staging.ddr-md-content.pages.dev)
           latest.json · manifest.json · objects/<sha256>.<ext>
                          │ polled on launch
                          ▼
                     installed apps
```

## What exists, and who owns it

| Piece | Where | Managed by |
|---|---|---|
| Pages project `ddr-md-content` | Cloudflare | Terraform |
| CI deploy token (Pages Write only) | Cloudflare, account-owned | Terraform |
| Private repo `sh1ggy/ddr-md-content` | GitHub | Terraform (archived, not deleted, on destroy) |
| Its `.github/workflows/publish.yml` | content repo | Terraform, from [publish.yml.tftpl](publish.yml.tftpl) |
| `CLOUDFLARE_API_TOKEN` secret, `CONTENT_URL` / `STAGING_CONTENT_URL` / `PAGES_PROJECT` / `CLOUDFLARE_ACCOUNT_ID` variables | content repo | Terraform |
| The publish logic | [publish-content.yml](../.github/workflows/publish-content.yml) here | git |
| The content itself | content repo's commits | you (pushed from prep output) |
| Content id | the live `manifest.json`: a hash of what's published, with `source` naming the commits | CI |
| Terraform state | `infra/terraform.tfstate`, local, gitignored | you |
| Sync Worker `sync` (code in [sync/worker.js](sync/worker.js)) at `sync.<workers_subdomain>.workers.dev`, and its D1 database `ddr-md-sync` | Cloudflare | Terraform |
| Players' synced data | that D1 database | the app (see [Cloud Sync](#cloud-sync)) |
| Circles Worker `circles` (code in [circles/worker.js](circles/worker.js)) at `circles.<workers_subdomain>.workers.dev`, and its D1 database `ddr-md-circles` | Cloudflare | Terraform |
| Players' circles | that D1 database | the app (see [Circles](#circles)) |
| Optional `circles-uat` Worker (code/config in [circles/uat/](circles/uat/)) | Cloudflare, using the existing Circles API | `cf deploy` (see [production test people](#persistent-production-test-people)) |

## Reproducible from scratch?

The core content, sync and Circles services, yes: `terraform apply` recreates
them. The optional production test Worker is recreated with `cf deploy` as
described below. Not covered by Terraform:

- **Bootstrap credentials.** A Cloudflare token with *Account › Cloudflare
  Pages › Edit*, *Account › Account API Tokens › Edit*, *Account › Workers
  Scripts › Edit* and *Account › D1 › Edit* (dashboard only; no CLI can mint
  one), and a GitHub token with `workflow` scope.
- **Players' synced data.** It lives only in D1. `terraform destroy` or a
  replaced database loses every backup; each app uploads its own data again
  at its next sync, but whatever only lived on a lost phone is gone. Back
  it up with `cf d1 export` before risky changes.
- **The content.** It lives in the content repo's history, so it survives
  anything short of deleting that repo. If you need to push it again, copy
  `songs/`, `steps/`, `jackets/`, `jackets-160/` from a DDR-BPM-prep run.
- **The state file.** Lose it and Terraform forgets what it made. See
  [Lost state](#lost-state). Keep a copy somewhere safe.

## Set up from scratch

```bash
brew install hashicorp/tap/terraform
gh auth refresh -h github.com -s workflow
cf auth login && cf accounts list          # account ID (or the dashboard URL)
```

Create the bootstrap Cloudflare token (permissions above). Copy
[terraform.tfvars.example](terraform.tfvars.example) to `terraform.tfvars`
(gitignored), fill in the account ID, and either put the token in it as
`cloudflare_api_token` or load it per session instead:

```bash
read -s "CLOUDFLARE_API_TOKEN?Cloudflare token: " && export CLOUDFLARE_API_TOKEN
```

Then, from `infra/`:

```bash
terraform init
GITHUB_TOKEN=$(gh auth token) terraform apply
```

Expect *9 to add*.
Committing the workflow file triggers a run that fails on an empty repo; that's
expected. Then push the content:

```bash
git clone git@github.com:sh1ggy/ddr-md-content.git && cd ddr-md-content
for d in songs steps jackets jackets-160; do cp -R ~/repos/ddr-md/assets/$d .; done
git add -A && git commit -m "content: from DDR-BPM-prep" && git push
```

The first publish uploads ~660 MB and takes about 4½ minutes. Check it:

```bash
curl -s https://ddr-md-content.pages.dev/latest.json
```

## Day to day

| To... | Do |
|---|---|
| Publish new songs / chart fixes | Copy prep output into `ddr-md-content`, commit, push to `master` (other branches don't publish, except `staging`) |
| Try a chart before it goes live | Push it to the content repo's `staging` branch (branch it from `master`). It publishes to the staging URL with the same checks; run a build with `--dart-define=CONTENT_URL=https://staging.ddr-md-content.pages.dev` to take it. Happy → merge into `master` and push |
| Publish generator or parity engine changes | Merge to `workflow_ref`; the daily run picks it up, or `gh workflow run Publish -R sh1ggy/ddr-md-content` |
| Make a store build | `bash scripts/build_store.sh ipa` (or `appbundle`): fetches the live content, then builds with `CONTENT_URL` set |
| Remove a song | Delete its four files, add its name to `removed.txt` in `ddr-md-content`, push. Without the `removed.txt` line CI refuses |
| Watch a publish | `gh run list -R sh1ggy/ddr-md-content` |
| Find what a publish was built from | `curl -s <content_url>/manifest.json \| jq .source`: the content and ddr-md commits it was first built from |
| Try ddr-md changes before merging | Set `workflow_ref` to the branch and apply; set it back to `master` and apply again **before** deleting the branch, or every run fails |
| Roll back a bad publish | Revert the commit in `ddr-md-content` and push. Apps follow whatever is live, so they take the old files like any update |

### Adding one song

Run prep for it, then copy its four files into `ddr-md-content` and push:

```
songs/<name>.json        metadata: title, artist, version, BPM, levels, radar
steps/<name>.json        the charts
jackets/<name>.png       full jacket
jackets-160/<name>.png   list thumbnail
```

CI derives everything else: the songlist, the song's pattern file, the
levels table its charts are ranked in, and the WebP jackets the app reads
(`jackets-webp/`, `jackets-160-webp/`; the PNGs still publish for older apps). Existing songs' files don't change
(ranks are computed on the device), so each install downloads about 700 KB:
the songlist (567 KB compressed, replaced whole), both WebP jackets (~60 KB), the
levels table (58 KB), and ~10 KB of steps and patterns. `<name>` must match
across all four files and never change afterwards.

A run with nothing changed skips the deploy, so the daily run costs only
Actions minutes (~4–5 of the private repo's 2,000 free per month).

## Changing the infra

Edit the `.tf` files, then `GITHUB_TOKEN=$(gh auth token) terraform plan` / `apply`,
with the bootstrap token in `terraform.tfvars` or loaded as above. Never hand-edit the content repo's workflow, secret or
variables; the next apply overwrites them.

To rotate the CI token: `terraform apply -replace=cloudflare_account_token.ci`
(the secret updates in the same apply).

## Lost state

Recreate `terraform.tfvars`, `terraform init`, then adopt what exists:

```bash
terraform import cloudflare_pages_project.content '<account_id>/ddr-md-content'
terraform import github_repository.content ddr-md-content
terraform import 'github_repository_file.publish' 'ddr-md-content:.github/workflows/publish.yml:'
for v in CONTENT_URL PAGES_PROJECT CLOUDFLARE_ACCOUNT_ID; do
  terraform import "github_actions_variable.content[\"$v\"]" "ddr-md-content:$v"
done
```

For the sync server, with the D1 database id from `cf d1 list`:

```bash
terraform import cloudflare_d1_database.sync '<account_id>/<database_id>'
terraform import cloudflare_workers_script.sync '<account_id>/sync'
```

Don't import the CI token or its secret: a token's value can't be read back.
Delete the old *ddr-md-content CI deploy* token in the Cloudflare dashboard
(*Manage Account › Account API Tokens*) and let `terraform apply` create a new
one and update the secret.

## What can go wrong

Every failure below either leaves players on the content they already have,
or is caught before it ships. The ones that need you are marked.

| Failure | What happens |
|---|---|
| Phone offline, host down, request fails mid-download | The update is retried next launch (or from Settings → Song Updates). Downloads land as `.part` files, are hash-checked, and the overlay swaps in with one rename, so a half-finished update is never read |
| A downloaded file is corrupt | Its sha256 doesn't match the manifest: the whole update is abandoned, the current content stays |
| An app update ships with different content than a phone downloaded | A download only applies to the bundle it was diffed against, so the app re-syncs from its new bundle |
| Patterns made by a different parity engine | Skipped (`engine` ≠ the app's `kPatternEngineVersion`); the app keeps its own patterns |
| Content in a shape an older app can't read | Can't happen if changes stay additive; a breaking one ships at a new path that older apps never download (AGENTS.md) |
| ddr-md `master` breaks a generator | CI fails before deploying; live content is untouched. GitHub emails you about the failed run |
| A bad prep run (missing steps, truncated songlist) | The pre-deploy check fails the run if any listed song lacks steps |
| A song renamed or dropped by accident | CI fails if any live song disappears without being named in the content repo's `removed.txt`; a rename looks like remove + add, which would orphan players' scores, notes and footing edits |
| A parity change without a `kPatternEngineVersion` bump | CI fails if counts change for any song whose charts didn't, while `engine` still matches live |
| A store build bundling stale or local content | `scripts/build_store.sh` always fetches the live content first |
| Live manifest briefly unreachable from CI | The run fails rather than publishing without its checks |
| Pages project recreated, or rolled back in the dashboard | Nothing to restore: the next publish redeploys the content repo's files, and apps follow it |
| Two publishes at once | They queue (`concurrency: publish-content`); deploys are atomic, so a phone never sees a half-uploaded publish |
| CI and a Mac generate different bytes | Was real (level order in `pattern_levels.json`); fixed and checked: a local build matches the live publish file for file |

**Needs you:**

- **Bump `kPatternEngineVersion`** when CI tells you to (it can't bump it for
  you: the number ships inside the app).
- **Use `scripts/build_store.sh`** for store builds rather than `flutter build`
  directly.
- **Keep the state file and the bootstrap token.** Losing the state is
  recoverable ([Lost state](#lost-state)); applies need the token, so give it
  an expiry measured in months.
- **Content repo size.** ~675 MB now; jackets in git history only grow.

## Limits to keep in mind

- Pages: 20,000 files per deploy and 25 MiB per file (free plan). Content is
  ~5,060 files, about 4 per song.
- The content repo is ~675 MB of plain git. GitHub starts warning near 1 GB;
  past that, prune jacket history or move jackets to Git LFS.
- Pages serves the content publicly; the content repo is what's private.
- Sync atomically enforces 20,000 rows/player/day and 30,000/network/day.
  Empty uploads do not create accounts. New account creation is limited to
  200/day independently of established accounts; there is no shared mutation
  kill switch. Request limits aggregate IPv6 addresses by /64. These controls
  do not guarantee availability or a spending cap: requests still invoke a
  Worker, and distributed abuse can exhaust free platform quotas.

## Cloud Sync

Optional backup of players' own data, between their devices, at
`https://sync.ddr-md.workers.dev`. Turned on per device under Home →
Settings → Cloud Backup. Release builds point at the live server by
default; others need `--dart-define=SYNC_URL=…` (the `sync_url` output,
which needs `workers_subdomain` in `terraform.tfvars`) or don't offer it.
The account's workers.dev subdomain is `ddr-md`, so the Worker's address
is `<sync_worker>.ddr-md.workers.dev`; changing either moves the server out
from under released apps.

- **No sign-in.** The app makes a random 256-bit key on first use and sends
  it as a bearer token; the server keys everything on its SHA-256. On iOS
  the key lives in the Keychain (synced by iCloud Keychain), and on every
  platform in preferences (Android's backup restores it on a new phone).
  The DDR-CODE, when known, is stored as a label only.
- **Encrypted storage.** The server does not interpret app rows. It encrypts
  their payloads and original keys with AES-256-GCM and indexes row keys with
  HMAC-SHA-256, using a Worker secret outside D1. The optional DDR-CODE label
  is encrypted too. This is server-side encryption, not end-to-end encryption.
  The API still returns the original JSON to the authenticated owner;
  every accepted write gets a per-user revision, and a device pulls
  everything after its cursor. The latest edit to a row wins: an older
  write keeps the stored data but still takes a new revision, so the
  device that sent it pulls the winner back. Times from a clock running
  ahead are clamped to the server's. Deletes are kept as rows with no
  data. A push reports the account's revision, so a device that was the
  only writer skips pulling its own rows back; a pull reports it too, so a
  device ahead of the server (data lost) uploads everything again.
- **The app** (`lib/models/cloud_sync.dart`) records every changed row in
  `sync_outbox` with SQLite triggers, pushes those rows as they are now,
  then pulls and applies, mapping venue and cabinet ids to their uids.
  Adding a synced table means adding it to `syncTables` and giving it
  triggers in a migration; the server needs no change.

Try it locally: put [sync/worker.js](sync/worker.js) behind a `cf dev`
project with a D1 binding named `DB`, a 64-character hex `DATA_KEY` secret,
and the request/safety rate bindings in `main.tf`, then run the app with
`--dart-define=SYNC_URL=http://localhost:<port>`.

## Circles

Players following and cheering each other, at
`https://circles.ddr-md.workers.dev`. Off until a player starts a circle on
the Circle tab. All builds default to the deployed server. Use
`--dart-define=CIRCLES_URL=http://localhost:8787` for local scenarios, or an
explicitly empty CIRCLES_URL to disable it.

- **Its own key.** Like cloud sync there's no sign-in, but the key is a
  separate one, so deleting a backup never loses a circle.
- **Known by dancer name and DDR-CODE**, filled from e-amusement when it's
  linked. Nobody checks them, and DDR-CODEs show on the cabinet, so a code
  isn't unique here: people are told apart by an opaque id derived from the
  key.
- **The server reads rows**, unlike sync: it checks who may see whom. A
  player has one circle, joined by scanning its QR or typing the invite code
  under it (8 characters with no 0/O or 1/I, good for a day); whoever has
  it is in. Two players in each other's circles are
  friends; joining can let the leader into the joiner's circle too, so one
  scan makes friends. Removing a player revokes the current invite and blocks
  that identity from rejoining, including after code rotation. The owner can
  still be impersonated by a different self-asserted identity; only share
  invites with trusted people. Code lookups are capped per player per day,
  and mutations at 600/player/day. New profiles have a separate 200/day
  admission limit. These are abuse controls, not a guaranteed spending cap.
- **Live sessions and cheers.** A broadcast session shows on its player
  (venue, credit, side) until it ends or lapses after two hours. After each
  e-amusement sync during one, the app shares the session's credits (songs,
  scores, fails, new bests), and the circle can cheer each with one of a few
  preset cheers (no free text, nothing to moderate). Credits and cheers
  disappear from feeds after two days; scheduled cleanup deletes expired
  credits/cheers and live broadcasts in bounded batches every five minutes,
  including for inactive players. The app polls only while it shows live people or your own
  broadcast: once a minute on the Circle tab and the live card, every half
  minute on someone's page.

### Trying it locally

[circles/dev/](circles/dev/) runs the Worker on Node's SQLite, no Cloudflare
needed (Node 22+):

```bash
node infra/circles/dev/worker_test.mjs            # the Worker end to end
node infra/circles/dev/server.mjs --fresh         # http://localhost:8787
flutter run -d macos --dart-define=DB_NAME=timing-preview.db --dart-define=CIRCLES_URL=http://localhost:8787 --dart-define=CIRCLES_KEY=dev-you____________________________________
node infra/circles/dev/scenario.mjs               # lists the scenarios
node infra/circles/dev/scenario.mjs seed          # e.g. a circle to look at
```

`CIRCLES_KEY` (debug localhost builds only) fixes the app's key to the one
scenario.mjs calls "you", so a scenario can set up your circle or have
made-up players join it, leave or take you out of theirs. Pull to refresh on the
Circle tab to see each land. Add a scenario to `scenarios` in
scenario.mjs for each new circle feature.

To preview incoming cheer toasts, start a session with **Broadcast to my
circle** enabled, then run `node infra/circles/dev/scenario.mjs cheered`.
It uses the broadcast's session id and posts a sample credit if needed, so
no arcade sync is required. While you broadcast, incoming cheers are checked
every 30 seconds while the app is in the foreground and appear as brief toasts.
Existing cheers are not replayed on startup. Repeating the scenario changes
the preset cheers so you can test another arrival. Broadcast and Show my location are
chosen once for the session; location is off by default.

The Circles Worker and D1 database are deployed and recorded in the main
checkout's Terraform state. The cf OAuth login can deploy; Terraform's
account-token data sources require the bootstrap API token described above.

### Security checks and deployment

Run `node infra/security_test.mjs`,
`node infra/circles/dev/worker_test.mjs`, and
`node infra/circles/uat/worker_test.mjs` for offline security/behavior checks;
`flutter test test/cloud_sync_test.dart test/cloud_sync_http_test.dart` checks
client convergence and large Unicode upload splitting. Validate Terraform
with `terraform -chdir=infra validate`. Use the cached cf/Miniflare runtime
for workerd checks before a deployment. These checks do not constitute a
production load test or proof of DDoS immunity.

`data_crypto.js` is an additional module for both Terraform Worker uploads.
Both Workers require distinct, stable `DATA_KEY` secrets (32 random bytes as
64 hex characters) and `MAINTENANCE_KEY` secrets. Keep them outside Terraform
state; `keep_bindings = ["secret_text"]` preserves secrets on Terraform
uploads. Back up encryption keys securely. Never generate a replacement data
key over an existing encrypted database: old data needs its original key.
A code rollback must retain encrypted-row support and the same key.

Sync accepts at most 8 MiB per upload. New clients split uploads at 512 KiB.
Every private response has `no-store`. The request bindings are 120/key/min,
600/network/min, and, for Circles, 30 invite operations/network/min. All
DELETE requests instead use `SAFETY_RATE` (30/key/min), preserving deletion
and revocation when mutation/network allowances are exhausted. Missing rate
bindings fail closed in production. Sync daily counters, revisions and writes
commit or roll back together. Daily shared counters are telemetry only.

Circles stores live venue names encrypted. New app versions use
`POST /v1/code/lookup`; the legacy invite GET route stays compatible.
Automatic invocation logs are disabled and logs/traces are not persisted,
since legacy URLs contain invite capabilities. Only allowlisted operational
event names/counts are logged. Use platform request/error metrics and the
account's unexpected-spend notification for operations. The $1 account budget
notification is managed separately through `cf alerting`, not the pinned
Terraform provider (which lacks its filter); it is an alert, not a cap.

Both Workers expose a maintenance endpoint restricted to `MAINTENANCE_KEY`:
`POST /internal/maintenance`. It performs bounded legacy encryption and
retention cleanup, and returns counts only. On Circles, the administrative
`X-Revoke-Invites: 1` header also revokes existing invite codes; scheduled
cleanup does not revoke unexpired codes. Run maintenance until no legacy
rows remain after deploying encryption support. Older D1 recovery snapshots
can contain plaintext until Cloudflare's recovery retention expires.

Terraform configures five-minute maintenance schedules, explicitly disables
version preview URLs, and prevents destruction of either D1 database while
its lifecycle guard is present. Deploy matching code, helper module and
bindings together. The production workers.dev URLs remain enabled for
released apps. No paid plan is enabled here; an owned zone is needed for
hostname WAF rules before Worker invocation. Work through a compatible
hostname migration before disabling workers.dev.

The November security deployment used cached cf OAuth because the bootstrap
API token in the local tfvars was invalid. Terraform source is updated and
validated, but a full Terraform refresh/apply still needs a valid bootstrap
token. The private `_private/security-deploy/` directory holds the deployment
configuration, secret files and evidence; its encryption-key backup is under
`_private/backups/`, never in git. Preserve those keys when restoring infra.

Public fixture keys are accepted by the app only for localhost testing;
remote scenario execution requires explicit --allow-remote-fixtures and
must contain only disposable fake data.

### Persistent production test people

The reusable `circles-uat` Worker in [circles/uat/](circles/uat/) maintains
three private test profiles for one explicitly configured Circles profile
id. It uses the normal production API and existing database: no additional
database, queue or storage service. This optional Worker and its minute cron
are managed with `cf` and `cloudflare.config.ts`, separately from Terraform.
Extend this Worker for future automated Circles scenarios.

- **MIKA** follows the target and cheers each shared credit while live.
  After a session ends (or its broadcast expires), the final credit gets
  LEGEND, matching the app's existing session cheer behaviour. A 15-second
  grace period lets the app establish its notification baseline. Broadcasts
  without shared credits have nothing to cheer yet.
- **REXX** is a mutual friend, always live at UAT Arcade with three sample
  credits (including a fail and a new best). The sample session rolls daily;
  its live status is renewed hourly before the two-hour expiry.
- **TOFU** is a mutual friend with no broadcast or shared credits.

These are real test profiles visible through normal Circles permissions;
MIKA's cheers are visible to anyone who can see the target's shared credits.
Only the configured profile id is targeted, never a dancer name or DDR-CODE.
The scheduled Worker has no database binding or real player's key. It never
reattaches removed profiles. Removing MIKA from the target's circle stops all
automated activity; removing REXX stops its sample activity.

From `infra/circles/uat/` (Node 22.18+ and a Cloudflare login):

```bash
npm ci
node worker_test.mjs
node manage.mjs setup <target-profile-id>
cf deploy --secrets-file .secrets.json
node manage.mjs status
node manage.mjs tick                 # run the same scenario immediately
node manage.mjs reset                # disable automation, delete only the three test profiles
```

Setup reads the existing Circles database id/account from the local
Terraform state, checks the target profile, creates three profiles with
cryptographically random private keys and attaches their memberships. The
keys are saved with owner-only permissions in gitignored `.secrets.json`
and deployed as the Worker's `UAT_CONFIG` secret. Repeating setup for the
same target reuses those identities; reset is required to change targets.
Keep that file to manage or remove the profiles later. Cron changes can
take up to 15 minutes to propagate. Missing `UAT_CONFIG` disables the job;
there is no public HTTP control endpoint or workers.dev route.
