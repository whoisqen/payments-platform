# eks

EKS cluster `pay-<env>-<region-short>-<component>`: private endpoint only, Secrets envelope encryption with a customer managed key,
access entries (authentication mode API, no creator admin), IAM OIDC provider, five control-plane log types in an encrypted log group.
Managed add-ons: vpc-cni (prefix delegation, pod identity), kube-proxy, eks-pod-identity-agent, coredns, aws-ebs-csi-driver.
A three-node Bottlerocket On-Demand bootstrap group (IMDSv2, hop limit 1, encrypted gp3) hosts CoreDNS and Karpenter; Karpenter provisions the rest.
Required: `region`, `environment`, `component`, `kubernetes_version`, `vpc_id`, `vpc_cidr_block`, `subnet_ids`, three key ARNs, `permissions_boundary_arn`, `tags`.
Locker pod group egress (strict pod SG mode): 443 to the endpoint group or `locker_pod_endpoint_cidrs`, 5432 to `locker_pod_database_cidrs`, DNS 53 and istiod 15012; empty lists use the VPC CIDR.
Test: `terraform init -backend=false && terraform test` (mock provider).
