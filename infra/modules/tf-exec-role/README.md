# tf-exec-role

Role `<prefix>-<root>-tf-exec` in an account of a state root: the generated provider of every unit assumes it.
Trust: the shared-services account, limited by `aws:PrincipalArn` to `<prefix>-<root>-glob-tf-plan` and `<prefix>-<root>-glob-tf-apply-*`.
Rights: AdministratorAccess; the SCPs are the limit (an optional boundary would block the service roles some modules create).
First apply with `PAY_TF_DIRECT=true`: shared-services credentials for the state, the provider enters the account through `PAY_TF_DIRECT_ROLE` (default `OrganizationAccountAccessRole`; set an administration role for management).
Test: `terraform init -backend=false && terraform test`.
