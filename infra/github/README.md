# infra/github

GitHub organization and repository settings as code (section 10). Nothing here is applied: every real value is a `CHANGEME` placeholder.

```
infra/github/
  main.tf, variables.tf, versions.tf   wiring only: calls the modules, holds the placeholder variables
  backend.hcl.example                  state bucket placeholder
  config/owners.yaml                   path to team mapping, source of CODEOWNERS
  modules/
    organization/   base permission, no repository creation by members
    repository/     repository, vulnerability alerts, Actions allowlist, read-only GITHUB_TOKEN
    rulesets/       main (2 approvals, CODEOWNERS, signatures, linear history, merge queue, ci-gate, spec-gate), tags v*
    environments/   dev, stage, prod (SRE), cde-prod (SRE and security), deployments from main only
    codeowners/     renders config/owners.yaml into CODEOWNERS at the repository root
```

Each module has `variables.tf`, `versions.tf`, `main.tf` and `tests/` with a mocked provider.

## Use

```sh
cp backend.hcl.example backend.hcl            # fill the state bucket
export TF_VAR_github_app_pem="$(cat app.pem)" # never commit the key
terraform init -backend-config=backend.hcl
terraform plan
```

Offline tests: `for m in modules/*; do terraform -chdir=$m init -backend=false && terraform -chdir=$m test; done`.

## Personal account instead of an organization

`-var account_type=user` skips the organization settings, the team reviewers, the CODEOWNERS file and the merge queue (they exist only for organizations). Use `-var github_token` via `TF_VAR_github_token` for a token instead of the GitHub App, `-var import_existing=true` to adopt a repository that already exists, and `-var 'tag_bypass={actor_id=5,actor_type="RepositoryRole"}'` so that repository admins can create `v*` tags.

## Not covered by the provider

- Enforcing 2FA for the organization: a setting in the GitHub UI, check it manually.
- Private vulnerability reporting: enable it in the repository settings; `SECURITY.md` assumes it.
- Squash merge (section 10) and rebase merge (section 27) disagree: `allow_squash_merge` and `allow_rebase_merge` are variables.
