include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/fis-prereqs.hcl"
  expose = true
}

# Prod gets boundary and chaos-stop because fis-experiments creates its roles there too; no MSK reboot document.
inputs = {
}
