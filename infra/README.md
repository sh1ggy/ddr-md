# Content infrastructure

How chart content (songs, steps, patterns, jackets) reaches installed apps
without a store release, and how to rebuild, change or recover the infra
behind it. App-side behaviour is in [AGENTS.md](../AGENTS.md) (data flow §6).

```
DDR-BPM-prep ──copy──▶ ddr-md-content (private repo)
                          │ push / daily 03:17 UTC / manual
                          ▼
            .github/workflows/publish.yml   (written by Terraform)
                          │ calls
                          ▼
   ddr-md/.github/workflows/publish-content.yml @ workflow_ref
     generate songlist + patterns → content_manifest → wrangler deploy
                          │ only when something changed
                          ▼
         Cloudflare Pages: ddr-md-content.pages.dev
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
| `CLOUDFLARE_API_TOKEN` secret, `CONTENT_URL` / `PAGES_PROJECT` / `CLOUDFLARE_ACCOUNT_ID` variables | content repo | Terraform |
| The publish logic | [publish-content.yml](../.github/workflows/publish-content.yml) here | git |
| The content itself | content repo's commits | you (pushed from prep output) |
| Content number | the live `manifest.json` | CI (live + 1 when files change) |
| Terraform state | `infra/terraform.tfstate`, local, gitignored | you |

## Reproducible from scratch?

Everything in the cloud, yes: `terraform apply` recreates all of it. Not
covered by Terraform:

- **Bootstrap credentials.** A Cloudflare token with *Account › Cloudflare
  Pages › Edit* and *Account › Account API Tokens › Edit* (dashboard only;
  no CLI can mint one), and a GitHub token with `workflow` scope.
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

Expect *8 to add*.
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
| Publish new songs / chart fixes | Copy prep output into `ddr-md-content`, commit, push |
| Publish generator or parity engine changes | Merge to `workflow_ref`; the daily run picks it up, or `gh workflow run Publish -R sh1ggy/ddr-md-content` |
| Make a store build | `bash scripts/build_store.sh ipa` (or `appbundle`): fetches the live content, then builds with `CONTENT_URL` set |
| Remove a song | Delete its four files, add its name to `removed.txt` in `ddr-md-content`, push. Without the `removed.txt` line CI refuses |
| Watch a publish | `gh run list -R sh1ggy/ddr-md-content` |
| Try ddr-md changes before merging | Set `workflow_ref` to the branch and apply; set it back to `master` and apply again **before** deleting the branch, or every run fails |
| Roll back a bad publish | Revert the commit in `ddr-md-content` and push. The republish gets a *higher* content number with the old files, so apps take it like any update |

### Adding one song

Run prep for it, then copy its four files into `ddr-md-content` and push:

```
songs/<name>.json        metadata: title, artist, version, BPM, levels, radar
steps/<name>.json        the charts
jackets/<name>.png       full jacket
jackets-160/<name>.png   list thumbnail
```

CI derives everything else: the songlist, the song's pattern file, and the
levels table its charts are ranked in. Existing songs' files don't change
(ranks are computed on the device), so each install downloads about 900 KB:
the songlist (567 KB compressed, replaced whole), both jackets (~260 KB), the
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

Don't import the CI token or its secret: a token's value can't be read back.
Delete the old *ddr-md-content CI deploy* token in the Cloudflare dashboard
(*Manage Account › Account API Tokens*) and let `terraform apply` create a new
one and update the secret.

## What can go wrong

Every failure below either leaves players on the content they already have,
or is caught before it ships. The ones that need you are marked.

| Failure | What happens |
|---|---|
| Phone offline, host down, request fails mid-download | The update is retried next launch. Downloads land as `.part` files, are hash-checked, and the overlay swaps in with one rename, so a half-finished update is never read |
| A downloaded file is corrupt | Its sha256 doesn't match the manifest: the whole update is abandoned, the current content stays |
| A store build ships newer content than a phone downloaded | The bundle's content number is higher, so the old download is ignored |
| Patterns made by a different parity engine | Skipped (`engine` ≠ the app's `kPatternEngineVersion`); the app keeps its own patterns |
| Content in a shape an older app can't read | Skipped (`format` ≠ `kContentFormat`), as long as the format was bumped |
| ddr-md `master` breaks a generator | CI fails before deploying; live content is untouched. GitHub emails you about the failed run |
| A bad prep run (missing steps, truncated songlist) | The pre-deploy check fails the run if any listed song lacks steps |
| A song renamed or dropped by accident | CI fails if any live song disappears without being named in the content repo's `removed.txt`; a rename looks like remove + add, which would orphan players' scores, notes and footing edits |
| A parity change without a `kPatternEngineVersion` bump | CI fails if counts change for any song whose charts didn't, while `engine` still matches live |
| A store build bundling stale or local content | `scripts/build_store.sh` always fetches the live content first |
| Live manifest briefly unreachable from CI | The run fails rather than restarting the content number |
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
