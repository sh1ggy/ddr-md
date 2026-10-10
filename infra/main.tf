# Hosting and CI for over-the-air chart content (see README "Content Updates").
#
#   Cloudflare: the Pages project that serves build/content, and an
#               account-owned token that can only deploy to Pages.
#   GitHub:     the private content repo (raw songs, steps, jackets), its
#               publish workflow, and the secret + variables that workflow reads.
#
# The token CI uses only ever lives in Terraform state and the repo secret.

terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.27"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

# Cloudflare: var.cloudflare_api_token, else CLOUDFLARE_API_TOKEN.
# GitHub: GITHUB_TOKEN (run with GITHUB_TOKEN=$(gh auth token)).
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  owner = var.github_owner
}

resource "cloudflare_pages_project" "content" {
  account_id        = var.cloudflare_account_id
  name              = var.pages_project
  production_branch = "main"
}

resource "cloudflare_pages_domain" "content" {
  count        = var.custom_domain == "" ? 0 : 1
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.content.name
  name         = var.custom_domain
}

data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = var.cloudflare_account_id
}

resource "cloudflare_account_token" "ci" {
  account_id = var.cloudflare_account_id
  name       = "${var.pages_project} CI deploy"
  policies = [{
    effect = "allow"
    permission_groups = [{
      id = one([
        for g in data.cloudflare_account_api_token_permission_groups_list.all.result :
        g.id if g.name == "Pages Write"
      ])
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    })
  }]
}

locals {
  content_url = var.custom_domain != "" ? "https://${var.custom_domain}" : "https://${cloudflare_pages_project.content.subdomain}"
}

resource "github_repository" "content" {
  name               = var.content_repo
  description        = "DDR MD chart content (songs, steps, jackets), published by CI"
  visibility         = "private"
  auto_init          = true
  archive_on_destroy = true
}

resource "github_repository_file" "publish" {
  repository          = github_repository.content.name
  file                = ".github/workflows/publish.yml"
  content             = templatefile("${path.module}/publish.yml.tftpl", { ref = var.workflow_ref })
  commit_message      = "ci: publish content (managed by Terraform in ddr-md/infra)"
  overwrite_on_create = true
}

resource "github_actions_secret" "cloudflare_token" {
  repository  = github_repository.content.name
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = cloudflare_account_token.ci.value
}

resource "github_actions_variable" "content" {
  for_each = {
    CONTENT_URL           = local.content_url
    PAGES_PROJECT         = cloudflare_pages_project.content.name
    CLOUDFLARE_ACCOUNT_ID = var.cloudflare_account_id
  }
  repository    = github_repository.content.name
  variable_name = each.key
  value         = each.value
}
