variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the Pages project"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Bootstrap token (Pages Edit + Account API Tokens Edit); unset falls back to CLOUDFLARE_API_TOKEN"
  type        = string
  sensitive   = true
  default     = null
}

variable "github_owner" {
  type    = string
  default = "sh1ggy"
}

variable "content_repo" {
  description = "Private repo holding the raw content"
  type        = string
  default     = "ddr-md-content"
}

variable "pages_project" {
  description = "Pages project name; also its <name>.pages.dev address when free"
  type        = string
  default     = "ddr-md-content"
}

variable "workflow_ref" {
  description = "ddr-md branch whose publish workflow and generators CI uses; a feature branch to try changes before merging"
  type        = string
  default     = "master"
}

variable "custom_domain" {
  description = "Optional domain (on this Cloudflare account) to serve content from"
  type        = string
  default     = ""
}

variable "sync_worker" {
  description = "Cloud sync Worker name, the first label of its address: <this>.<workers_subdomain>.workers.dev"
  type        = string
  default     = "sync"
}

variable "sync_database" {
  description = "Cloud sync D1 database name (renaming replaces the database and loses every backup)"
  type        = string
  default     = "ddr-md-sync"
}

variable "workers_subdomain" {
  description = "The account's workers.dev subdomain (dashboard: Workers & Pages), for the sync_url output"
  type        = string
  default     = ""
}
