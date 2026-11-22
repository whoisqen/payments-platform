mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn        = "arn:aws:eks:eu-central-1:111111111111:cluster/pay-dev-euc1-eks-cell-0"
      identity   = [{ oidc = [{ issuer = "https://oidc.eks.eu-central-1.amazonaws.com/id/ABC" }] }]
      vpc_config = [{ cluster_security_group_id = "sg-0cluster", subnet_ids = [], security_group_ids = [] }]
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:eu-central-1:111111111111:q" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef" }
  }
  mock_resource "aws_memorydb_cluster" {
    defaults = { arn = "arn:aws:memorydb:eu-central-1:111111111111:cluster/x" }
  }
}

run "stack_inputs_fit_the_modules" {
  command = plan
}
