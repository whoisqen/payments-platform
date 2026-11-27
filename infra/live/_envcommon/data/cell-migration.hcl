locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  # images.yml writes the digest of every image it builds into deploy/envs/<env>/images.yaml (key cell-copy)
  images_file = "${get_repo_root()}/deploy/envs/${local.env_cfg.environment}/images.yaml"
  digest      = try(yamldecode(file(local.images_file)).images["cell-copy"], null)
  registry    = "${local.env_cfg.cfg.registry.ecr_prefix}/${local.env_cfg.cfg.registry.ecr_repo_prefix}"
}

terraform {
  source = "${get_repo_root()}/infra/modules//cell-migration"
}

inputs = {
  # Image of the copy function by digest (docker/cell-copy); until images.yml has built it the documents exist and fail at the invoke step.
  image_uri                = local.digest == null ? null : "${local.registry}/cell-copy@${local.digest}"
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "card-data"
    backup-tier = "none"
  }
}
