variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the Pages project"
  type        = string
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
