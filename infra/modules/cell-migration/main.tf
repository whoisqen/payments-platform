locals {
  name          = "${var.name_prefix}-${var.environment}-${var.region_short}-cell-copy"
  function_name = local.name
  function_arn  = "arn:aws:lambda:${var.region}:${var.account_id}:function:${local.function_name}"
  cell_pattern  = "^(cell-[0-3]|spare)$"

  # scripts/cells/migrate-merchant.py starts these names with Merchant, SourceCell and TargetCell; the copy runs twice (copy, copy-delta), so it upserts.
  documents = {
    "cell-copy-merchant"   = { action = "copy", description = "Copies one merchant's rows from the source cell to the target cell; idempotent upsert, run before and during the write freeze." }
    "cell-verify-merchant" = { action = "verify", description = "Compares one merchant's rows between the source and the target cell; fails on any difference." }
  }
}

resource "aws_ssm_document" "this" {
  for_each = local.documents

  name            = each.key
  document_type   = "Automation"
  document_format = "YAML"
  tags            = var.tags

  content = yamlencode({
    schemaVersion = "0.3"
    description   = each.value.description
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      Merchant             = { type = "String", description = "merchant_id", allowedPattern = "^[A-Za-z0-9_-]{1,64}$" }
      SourceCell           = { type = "String", description = "Cell the merchant leaves", allowedPattern = local.cell_pattern }
      TargetCell           = { type = "String", description = "Cell the merchant moves to", allowedPattern = local.cell_pattern }
      AutomationAssumeRole = { type = "String", description = "Role of the execution", default = aws_iam_role.automation.arn }
    }
    mainSteps = [
      {
        name           = "differentCells"
        action         = "aws:executeScript"
        timeoutSeconds = 60
        inputs = {
          Runtime      = "python3.11"
          Handler      = "handler"
          InputPayload = { source = "{{ SourceCell }}", target = "{{ TargetCell }}" }
          Script       = "def handler(events, context):\n    if events['source'] == events['target']:\n        raise ValueError('source and target cell are the same')\n"
        }
      },
      {
        name           = each.value.action
        action         = "aws:invokeLambdaFunction"
        timeoutSeconds = 900
        maxAttempts    = 1
        inputs = {
          FunctionName   = local.function_name
          InvocationType = "RequestResponse"
          Payload        = jsonencode({ action = each.value.action, merchant = "{{ Merchant }}", source = "{{ SourceCell }}", target = "{{ TargetCell }}" })
        }
      },
      {
        name           = "checkResult"
        action         = "aws:executeScript"
        timeoutSeconds = 60
        isEnd          = true
        inputs = {
          Runtime      = "python3.11"
          Handler      = "handler"
          InputPayload = { payload = "{{ ${each.value.action}.Payload }}" }
          # A function error answers with an error object instead of {"ok": true}, so one check covers both.
          Script = "import json\ndef handler(events, context):\n    if not json.loads(events['payload']).get('ok'):\n        raise RuntimeError('cell copy failed: ' + events['payload'])\n"
        }
      },
    ]
  })
}

resource "aws_iam_role" "automation" {
  name                 = "${local.name}-automation"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "automation" {
  name = "invoke-copy"
  role = aws_iam_role.automation.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "InvokeCopy", Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = [local.function_arn] }]
  })
}

resource "aws_security_group" "function" {
  name        = local.name
  description = "Merchant copy between cells: PostgreSQL to the cell RDS proxies only."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_egress_rule" "to_proxy" {
  for_each = var.cells

  security_group_id            = aws_security_group.function.id
  referenced_security_group_id = each.value.proxy_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "RDS Proxy of ${each.key}"
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_function" {
  for_each = var.cells

  security_group_id            = each.value.proxy_security_group_id
  referenced_security_group_id = aws_security_group.function.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Merchant copy function"
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# Secrets Manager is reached through the interface endpoint of the VPC on 443; nothing outside the VPC.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.function.id
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Secrets Manager endpoint"
}

resource "aws_iam_role" "function" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "function_vpc" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "function" {
  name = "cell-logins"
  role = aws_iam_role.function.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadLogins", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [for c in values(var.cells) : c.login_secret_arn] },
      {
        Sid       = "DecryptLogins"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = var.secrets_kms_key_arns
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_lambda_function" "copy" {
  # checkov:skip=CKV_AWS_116: the automation step is the only caller and reports the failure; a dead-letter queue would hide it
  # checkov:skip=CKV_AWS_173: the environment holds endpoints and secret ARNs, no secret values
  count = var.image_uri == null ? 0 : 1

  function_name                  = local.function_name
  role                           = aws_iam_role.function.arn
  package_type                   = "Image"
  image_uri                      = var.image_uri
  architectures                  = ["arm64"]
  timeout                        = 900
  memory_size                    = 1024
  reserved_concurrent_executions = 1

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.function.id]
  }

  environment {
    variables = {
      CELLS = jsonencode({ for c, v in var.cells : c => { host = v.proxy_endpoint, secret = v.login_secret_arn } })
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}
