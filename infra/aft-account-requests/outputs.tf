output "requested_accounts" {
  value       = sort(keys(local.accounts))
  description = "Names of the accounts requested through AFT."
}
