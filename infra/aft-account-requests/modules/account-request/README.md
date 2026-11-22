# account-request

One AFT account request: an item of the `aft-request` DynamoDB table with the Control Tower parameters, the account
tags and the customization folder. Validates the name, the OU and that `pci-scope = cde` exists only in Workloads/CDE.
Local to `infra/aft-account-requests`; AFT picks the item up and creates the account.
