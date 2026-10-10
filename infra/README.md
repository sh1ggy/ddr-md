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

Create the bootstrap Cloudflare token (permissions above), then from `infra/`,
in one terminal:

```bash
read -s "CLOUDFLARE_API_TOKEN?Cloudflare token: " && export CLOUDFLARE_API_TOKEN
GITHUB_TOKEN=$(gh auth token) terraform init
GITHUB_TOKEN=$(gh auth token) terraform apply
```

Variables come from `terraform.tfvars` (gitignored; copy
[terraform.tfvars.example](terraform.tfvars.example)). Expect *8 to add*.
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
| Make a store build | `bash scripts/fetch_content.sh "$(terraform -chdir=infra output -raw content_url)"`, then build with `--dart-define=CONTENT_URL=<same url>` |
| Watch a publish | `gh run list -R sh1ggy/ddr-md-content` |
| Try ddr-md changes before merging | Set `workflow_ref` to the branch and apply; set it back after merging |

A run with nothing changed skips the deploy, so the daily run costs only
Actions minutes (~4–5 of the private repo's 2,000 free per month).

## Changing the infra

Edit the `.tf` files, then `terraform plan` / `apply` with the bootstrap
token loaded as above. Never hand-edit the content repo's workflow, secret or
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

## Limits to keep in mind

- Pages: 20,000 files per deploy and 25 MiB per file (free plan). Content is
  ~5,060 files, about 4 per song.
- The content repo is ~675 MB of plain git. GitHub starts warning near 1 GB;
  past that, prune jacket history or move jackets to Git LFS.
- Pages serves the content publicly; the content repo is what's private.
