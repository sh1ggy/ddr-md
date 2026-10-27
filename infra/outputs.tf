output "content_url" {
  description = "Pass to store builds: --dart-define=CONTENT_URL=<this>"
  value       = local.content_url
}

output "staging_content_url" {
  description = "For test builds: --dart-define=CONTENT_URL=<this>"
  value       = local.staging_content_url
}

output "content_repo" {
  value = github_repository.content.ssh_clone_url
}

output "sync_url" {
  description = "Pass to builds: --dart-define=SYNC_URL=<this>"
  value       = var.workers_subdomain == "" ? null : "https://${var.sync_worker}.${var.workers_subdomain}.workers.dev"
}
