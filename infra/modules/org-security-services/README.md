# org-security-services

GuardDuty, Security Hub, Inspector and Macie for the whole organization, run twice: `mode = management` in the management account, `mode = admin` in the audit account.

- management: designates `admin_account_id` as delegated administrator in every region of `regions` (Security Hub in `region_name` only; central configuration covers the rest).
- GuardDuty: every member auto-enabled (`ALL`) with S3, EKS audit logs, EBS malware protection, RDS login events, Lambda network logs and Runtime Monitoring with the EKS add-on.
- Security Hub: central configuration with a finding aggregator in `region_name`; one policy (PCI DSS v4.0.1, AWS FSBP, CIS v3.0.0) associated with `root_id`.
- Inspector: EC2, ECR, Lambda and Lambda code auto-enabled for new accounts; `member_account_ids` are associated and enabled now. Macie: auto-enable for new accounts plus a daily job over the S3 buckets of `cde_account_ids` (existing accounts must already be Macie members).
- `shield_advanced_enabled` subscribes only the account this stack runs in; protections stay with the protected resources.
