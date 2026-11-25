# org-policies

Organization policies from `policy/scp` attached to the root and OUs; runs in the management account.

- `*.json` become SCPs, `tag-policies/*.json` tag policies, `backup-policies/*.json` backup policies; the documents are attached as they are, never rewritten here.
- `policy_targets` maps each document name to keys of `target_ids`; a document without an entry fails the plan, `[]` keeps it unattached.
- A resource control policy on `rcp_targets` (the CDE OU) denies S3, KMS and Secrets Manager to principals outside `organization_id`; AWS service principals are exempt.
- Prerequisite: SCP, TAG_POLICY, BACKUP_POLICY and RESOURCE_CONTROL_POLICY enabled on the root (Control Tower owns the organization, not this module).
- Outputs: `policy_ids`, `policy_types`, `rcp_id`, `attachments`.
