# locker

Card vault chart on the `platform-common` library, canary-rolled by Istio weight.
`securityGroupPolicy.securityGroupIds` is required: the Terraform `locker_pod` security group
(`locker_pod_security_group_id`), the only one allowed to reach the card-vault Aurora proxy.
The value is `REPLACE_LOCKER_POD_SG_ID` until the env values set it.
The SecurityGroupPolicy needs `ENABLE_POD_ENI` on the VPC CNI.
