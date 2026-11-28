import unittest

import check_log_retention as c


class LogRetentionTest(unittest.TestCase):
    def test_repository_has_no_findings(self):
        found = [e for n, t in c.modules(c.INFRA).items() for e in c.check_module(n, t)]
        self.assertEqual(found, [])

    def test_log_group_without_retention_fails(self):
        text = 'resource "aws_cloudwatch_log_group" "x" {\n  name = "/x"\n}\n'
        self.assertEqual(len(c.check_module("m", text)), 1)

    def test_retention_zero_fails(self):
        text = 'resource "aws_cloudwatch_log_group" "x" {\n  name = "/x"\n  retention_in_days = 0\n}\n'
        self.assertIn("forever", c.check_module("m", text)[0])

    def test_lambda_without_its_group_fails(self):
        text = 'resource "aws_lambda_function" "f" {\n  function_name = "f"\n}\n'
        self.assertEqual(len(c.check_module("m", text)), 1)

    def test_lambda_with_group_passes(self):
        text = ('resource "aws_cloudwatch_log_group" "f" {\n  name = "/aws/lambda/f"\n  retention_in_days = 30\n}\n'
                'resource "aws_lambda_function" "f" {\n  function_name = "f"\n}\n')
        self.assertEqual(c.check_module("m", text), [])

    def test_log_bucket_needs_expiration(self):
        bucket = 'resource "aws_s3_bucket" "access_logs" {\n  bucket = "b"\n}\n'
        self.assertEqual(len(c.check_module("m", bucket)), 1)
        lifecycle = ('resource "aws_s3_bucket_lifecycle_configuration" "l" {\n  bucket = aws_s3_bucket.access_logs.id\n'
                     '  rule {\n    expiration {\n      days = 30\n    }\n  }\n}\n')
        self.assertEqual(c.check_module("m", bucket + lifecycle), [])


if __name__ == "__main__":
    unittest.main()
