# Restore tests run in the recovery region us-east-1, where the backup copies land.
include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/operations/restore-automation.hcl"
  expose = true
}
