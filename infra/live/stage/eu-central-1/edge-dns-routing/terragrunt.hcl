include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/edge/dns-routing.hcl"
  expose = true
}

dependency "dns" {
  config_path = "../edge-dns"

  mock_outputs = {
    zone_id = "Z00000000000MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

inputs = {
  zone_id = dependency.dns.outputs.zone_id
}
