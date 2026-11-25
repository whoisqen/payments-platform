# org-config

AWS Config for the whole organization, run twice: `mode = management` in the management account, `mode = admin` in the audit account.

- management: delegates `config`, `config-multiaccountsetup` and service-managed StackSets to `admin_account_id`.
- admin: organization aggregator over `regions`; a service-managed stack set (auto-deploy) puts a recorder and a delivery channel to the log archive (`config/` prefix, archive key) in every account of `recorder_target_ou_ids` and region; global resources are recorded in `region_name` only.
- admin: organization conformance pack from `policy/config/pci-dss-pack/pci-dss-v4.yaml` in every region, after the recorders.
- Set `recorder_stack_set_enabled = false` where Control Tower already owns the recorders, and `create_service_linked_role = false` where AWSServiceRoleForConfig exists. The management account itself is not covered by service-managed stack sets.
- Prerequisite: trusted access for config, config-multiaccountsetup and member.org.stacksets.cloudformation in the organization.
