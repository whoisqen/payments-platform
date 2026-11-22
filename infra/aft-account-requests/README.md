# aft-account-requests

A new account is one entry in `accounts/<ou>.yaml` and a pull request; each file is one OU of the table in section 3
(Infrastructure, Workloads/CDE, Workloads/NonCDE, Sandbox) and `modules/account-request` writes the AFT request item.
Not requested here: `management` (the organization root), `log-archive` and `audit` (created by Control Tower itself).
E-mails are placeholders on example.com: replace them with the real group aliases before the first apply.
`pci-scope = cde` is accepted only in Workloads/CDE. Runs in the AFT management account; the apply of cde-prod needs two approvals.
Test: `terraform init -backend=false && terraform test`.
