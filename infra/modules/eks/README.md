# eks

EKS cluster `pay-<env>-<region-short>-<component>`: private endpoint only, Secrets envelope encryption with a customer managed key,
access entries (authentication mode API, no creator admin), IAM OIDC provider, five control-plane log types in an encrypted log group.
Managed add-ons: vpc-cni (prefix delegation, pod identity), kube-proxy, eks-pod-identity-agent, coredns, aws-ebs-csi-driver.
A three-node Bottlerocket On-Demand bootstrap group (IMDSv2, hop limit 1, encrypted gp3) hosts CoreDNS and Karpenter; Karpenter provisions the rest.
Required: `region`, `environment`, `component`, `kubernetes_version`, `vpc_id`, `vpc_cidr_block`, `subnet_ids`, three key ARNs, `permissions_boundary_arn`, `tags`.
Test: `terraform init -backend=false && terraform test` (mock provider).
