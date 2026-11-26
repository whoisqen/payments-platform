output "guardduty_detector_ids" {
  description = "Detector of the delegated administrator per region (admin mode)."
  value       = { for r, d in data.aws_guardduty_detector.this : r => d.id }
}

output "securityhub_configuration_policy_id" {
  description = "Central Security Hub configuration policy; null outside admin mode."
  value       = one(aws_securityhub_configuration_policy.this[*].id)
}

output "securityhub_standard_arns" {
  description = "Standards enabled through the central configuration."
  value       = [for s in var.securityhub_standards : "arn:aws:securityhub:${var.region_name}::standards/${s}"]
}

output "macie_job_id" {
  description = "Daily Macie job over the CDE buckets; null when none."
  value       = one(aws_macie2_classification_job.cde[*].job_id)
}

output "delegated_regions" {
  description = "Regions per service where the audit account is delegated administrator (management mode)."
  value = {
    guardduty   = sort(keys(aws_guardduty_organization_admin_account.this))
    securityhub = [for a in aws_securityhub_organization_admin_account.this : var.region_name]
    inspector   = sort(keys(aws_inspector2_delegated_admin_account.this))
    macie       = sort(keys(aws_macie2_organization_admin_account.this))
  }
}
