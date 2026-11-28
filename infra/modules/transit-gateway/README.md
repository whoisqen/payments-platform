# transit-gateway

Transit gateway `pay-<env>-<region-short>-tgw` with default association and propagation disabled: every VPC attachment
is associated with exactly one named route table and propagates only to the tables listed in `propagate_to`.
`static_routes` hold the routes (a null attachment is a blackhole, for example CDE to platform).
`ram_principals` shares it with the organization; attachments are created in the provider's account, so spoke VPCs
in other accounts attach with their own resource and are associated by the hub (not covered here).
Peering to the shared-services hub: `transit-gateway-hub` (requester) and `transit-gateway-spoke` (accepter).
Test: `terraform init -backend=false && terraform test`.
