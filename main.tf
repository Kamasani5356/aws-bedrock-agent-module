########################################################################
# main.tf — AWS Bedrock Agent Terraform Module
# Registry refs:
#   aws_bedrockagent_agent          → hashicorp/aws
#   aws_bedrockagent_agent_alias    → hashicorp/aws
#   aws_bedrockagent_agent_action_group → hashicorp/aws
#   aws_iam_role / aws_iam_role_policy  → hashicorp/aws
#   aws_lambda_function             → hashicorp/aws
#   aws_cloudwatch_log_group        → hashicorp/aws
########################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

# ── Data sources ────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# ── IAM: Bedrock Agent Execution Role ───────────────────────────────────────
# The agent assumes this role at runtime.
# Trust policy: only the Bedrock service in this account may assume it.

data "aws_iam_policy_document" "agent_trust" {
  statement {
    sid     = "BedrockAgentTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    # Scope the trust down to this account only (security best practice)
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    # Restrict to agents in this account
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent/*"]
    }
  }
}

# Permission policy: allow the agent to call the chosen foundation model
data "aws_iam_policy_document" "agent_permissions" {
  # Allow invoking the specified foundation model
  statement {
    sid     = "InvokeFoundationModel"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/${var.foundation_model}"
    ]
  }

  # Allow the agent to retrieve from knowledge bases (if attached)
  statement {
    sid = "KnowledgeBaseQuery"
    actions = [
      "bedrock:Retrieve",
      "bedrock:RetrieveAndGenerate"
    ]
    resources = ["*"]
  }

  # Allow calling CloudWatch for logging
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/*"]
  }
}

resource "aws_iam_role" "bedrock_agent" {
  name               = "${var.name_prefix}-bedrock-agent-role"
  assume_role_policy = data.aws_iam_policy_document.agent_trust.json
  description        = "Execution role for Bedrock Agent: ${var.agent_name}"

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-bedrock-agent-role"
    ManagedBy = "terraform"
  })
}

resource "aws_iam_role_policy" "agent_permissions" {
  name   = "${var.name_prefix}-bedrock-agent-policy"
  role   = aws_iam_role.bedrock_agent.id
  policy = data.aws_iam_policy_document.agent_permissions.json
}

# Inline policy to allow agent → Lambda invocation (only if action group is enabled)
resource "aws_iam_role_policy" "agent_lambda_invoke" {
  count = var.create_action_group ? 1 : 0

  name = "${var.name_prefix}-bedrock-agent-lambda-invoke"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.agent_action[0].arn
      }
    ]
  })
}

# ── Lambda: Action Group Handler ─────────────────────────────────────────────
# A simple Python Lambda that the agent calls via its action group.
# Replace the handler code with your own business logic.

data "archive_file" "lambda_zip" {
  count       = var.create_action_group ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_payload.zip"

  source {
    content  = <<-PYTHON
import datetime
import json

def lambda_handler(event, context):
    """
    Action Group Lambda handler.
    Called by the Bedrock agent when it decides to invoke this action.
    Modify this logic to implement your actual business use case.
    """
    action_group  = event.get("actionGroup", "")
    api_path      = event.get("apiPath", "")
    http_method   = event.get("httpMethod", "GET")

    # ── Your custom business logic goes here ──────────────────────────
    now = datetime.datetime.utcnow()
    payload = {
        "date": now.strftime("%Y-%m-%d"),
        "time": now.strftime("%H:%M:%S"),
        "timezone": "UTC",
        "message": "Hello from Bedrock Agent Lambda!"
    }
    # ─────────────────────────────────────────────────────────────────

    response_body = {
        "application/json": {
            "body": json.dumps(payload)
        }
    }

    action_response = {
        "actionGroup":    action_group,
        "apiPath":        api_path,
        "httpMethod":     http_method,
        "httpStatusCode": 200,
        "responseBody":   response_body,
    }

    return {
        "messageVersion":        "1.0",
        "response":              action_response,
        "sessionAttributes":     event.get("sessionAttributes", {}),
        "promptSessionAttributes": event.get("promptSessionAttributes", {}),
    }
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_iam_role" "lambda_exec" {
  count = var.create_action_group ? 1 : 0

  name = "${var.name_prefix}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-lambda-exec-role" })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.create_action_group ? 1 : 0

  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "agent_action" {
  count = var.create_action_group ? 1 : 0

  function_name    = "${var.name_prefix}-bedrock-agent-action"
  role             = aws_iam_role.lambda_exec[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  description      = "Action Group Lambda for Bedrock Agent: ${var.agent_name}"

  environment {
    variables = var.lambda_env_vars
  }

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-bedrock-agent-action"
    ManagedBy = "terraform"
  })
}

# Allow Bedrock to invoke the Lambda (resource-based policy)
resource "aws_lambda_permission" "allow_bedrock" {
  count = var.create_action_group ? 1 : 0

  statement_id  = "AllowBedrockInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_action[0].function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent/*"
}

# ── CloudWatch Log Group ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "bedrock_agent" {
  name              = "/aws/bedrock/agent/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name      = "/aws/bedrock/agent/${var.name_prefix}"
    ManagedBy = "terraform"
  })
}

# ── Bedrock Agent ─────────────────────────────────────────────────────────────
# Registry: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent

resource "aws_bedrockagent_agent" "this" {
  # Required arguments
  agent_name              = "${var.name_prefix}-${var.agent_name}"
  agent_resource_role_arn = aws_iam_role.bedrock_agent.arn
  foundation_model        = var.foundation_model   # e.g. "anthropic.claude-3-sonnet-20240229-v1:0"
  instruction             = var.agent_instruction  # Min 40 chars

  # Optional arguments
  description                  = var.agent_description
  idle_session_ttl_in_seconds  = var.idle_session_ttl_in_seconds  # Default: 1800 (30 min), Max: 3600
  prepare_agent                = var.prepare_agent                 # Triggers agent preparation after create/update

  # Customer-managed KMS key (optional — leave null to use AWS-managed key)
  customer_encryption_key_arn = var.kms_key_arn

  # Guardrail configuration (optional — attach a Bedrock Guardrail)
  dynamic "guardrail_configuration" {
    for_each = var.guardrail_id != null ? [1] : []
    content {
      guardrail_identifier = var.guardrail_id
      guardrail_version    = var.guardrail_version
    }
  }

  # Memory configuration (optional — requires Bedrock memory enabled)
  dynamic "memory_configuration" {
    for_each = var.enable_memory ? [1] : []
    content {
      enabled_memory_types = ["SESSION_SUMMARY"]
      storage_days         = var.memory_storage_days
    }
  }

  tags = merge(var.tags, {
    Name             = "${var.name_prefix}-${var.agent_name}"
    FoundationModel  = var.foundation_model
    Environment      = var.environment
    ManagedBy        = "terraform"
  })

  depends_on = [
    aws_iam_role_policy.agent_permissions,
    aws_cloudwatch_log_group.bedrock_agent
  ]
}

# ── Bedrock Agent Action Group ────────────────────────────────────────────────
# Registry: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_action_group

resource "aws_bedrockagent_agent_action_group" "this" {
  count = var.create_action_group ? 1 : 0

  # Required arguments
  action_group_name = "${var.name_prefix}-action-group"
  agent_id          = aws_bedrockagent_agent.this.agent_id
  agent_version     = "DRAFT"   # Always DRAFT during development; point to a version for prod

  # Optional
  description                = "Action group for ${var.agent_name}: handles tool invocations via Lambda"
  skip_resource_in_use_check = true   # Allows delete without disabling first
  prepare_agent              = true   # Re-prepare agent after action group change

  # What executes when the agent picks this action group
  action_group_executor {
    lambda = aws_lambda_function.agent_action[0].arn
  }

  # Define available functions / API shape the agent can call
  function_schema {
    member_functions {
      functions {
        name        = "getDateTime"
        description = "Returns the current UTC date and time. Call this when the user asks about the current date or time."

        parameters {
          map_block_key = "format"
          type          = "string"
          description   = "Optional output format: 'date', 'time', or 'both'. Defaults to 'both'."
          required      = false
        }
      }

      functions {
        name        = "getHealthStatus"
        description = "Returns service health status. Call when user asks if the service is up."

        parameters {
          map_block_key = "service_name"
          type          = "string"
          description   = "Name of the service to check."
          required      = true
        }
      }
    }
  }

  depends_on = [
    aws_lambda_permission.allow_bedrock,
    aws_iam_role_policy.agent_lambda_invoke
  ]
}

# ── Bedrock Agent Alias ───────────────────────────────────────────────────────
# Registry: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_agent_alias
# An alias is required before the agent can be called from client code.
# Each alias points to a specific agent version. Creating an alias
# automatically creates a new immutable version of the agent.

resource "aws_bedrockagent_agent_alias" "this" {
  count = var.create_agent_alias ? 1 : 0

  # Required arguments
  agent_alias_name = var.agent_alias_name   # e.g. "prod", "v1", "live"
  agent_id         = aws_bedrockagent_agent.this.agent_id

  # Optional
  description = "Production alias for ${var.agent_name} — points to a pinned agent version"

  tags = merge(var.tags, {
    Name      = var.agent_alias_name
    ManagedBy = "terraform"
  })

  depends_on = [
    aws_bedrockagent_agent_action_group.this
  ]
}
