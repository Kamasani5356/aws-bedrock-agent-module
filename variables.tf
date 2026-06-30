########################################################################
# variables.tf — Input variables for the Bedrock Agent module
########################################################################

# ── General ──────────────────────────────────────────────────────────────────

variable "name_prefix" {
  description = "Prefix used to namespace all resource names (e.g. 'myapp-prod')."
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 30
    error_message = "name_prefix must be between 1 and 30 characters."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod). Used in tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Map of tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}

# ── Bedrock Agent ─────────────────────────────────────────────────────────────

variable "agent_name" {
  description = "Short name for the Bedrock agent (appended to name_prefix)."
  type        = string
  default     = "assistant"
}

variable "agent_description" {
  description = "Human-readable description of what the agent does."
  type        = string
  default     = "A Bedrock agent deployed via Terraform."
}

variable "foundation_model" {
  description = <<-EOT
    Bedrock foundation model ID for the agent to use.
    Examples:
      anthropic.claude-3-5-sonnet-20241022-v2:0   (Claude 3.5 Sonnet — recommended)
      anthropic.claude-3-sonnet-20240229-v1:0      (Claude 3 Sonnet)
      anthropic.claude-3-haiku-20240307-v1:0       (Claude 3 Haiku — fastest/cheapest)
      amazon.titan-text-premier-v1:0               (Amazon Titan)
    Check model availability for your region at:
    https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
  EOT
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "agent_instruction" {
  description = <<-EOT
    System instruction that defines the agent's persona and behavior.
    Must be at least 40 characters. Be specific — the quality of your instruction
    directly impacts the agent's response quality.
    Example:
      "You are a helpful customer support assistant for an e-commerce platform.
       You help users track orders, process returns, and answer product questions.
       Always be polite, concise, and escalate complex issues to a human agent."
  EOT
  type        = string

  validation {
    condition     = length(var.agent_instruction) >= 40
    error_message = "agent_instruction must be at least 40 characters (Bedrock API requirement)."
  }
}

variable "idle_session_ttl_in_seconds" {
  description = <<-EOT
    How long (in seconds) an idle session persists before conversation history is dropped.
    Min: 60 seconds. Max: 3600 seconds (1 hour).
    Recommended: 600 (dev), 1800 (prod).
  EOT
  type        = number
  default     = 1800

  validation {
    condition     = var.idle_session_ttl_in_seconds >= 60 && var.idle_session_ttl_in_seconds <= 3600
    error_message = "idle_session_ttl_in_seconds must be between 60 and 3600."
  }
}

variable "prepare_agent" {
  description = <<-EOT
    Whether to prepare (compile) the agent after creation or any update.
    Preparation is required before the agent can serve requests.
    Set to false only when you need to add action groups before first prepare.
  EOT
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = <<-EOT
    ARN of a customer-managed KMS key for encrypting agent resources.
    Leave null to use the default AWS-managed Bedrock KMS key.
  EOT
  type        = string
  default     = null
}

# ── Guardrail ────────────────────────────────────────────────────────────────

variable "guardrail_id" {
  description = <<-EOT
    ID of an existing Bedrock Guardrail to attach to the agent.
    Guardrails apply content filters and topic restrictions to every invocation.
    Leave null to skip guardrail attachment.
  EOT
  type        = string
  default     = null
}

variable "guardrail_version" {
  description = "Version of the Bedrock Guardrail to use. Required when guardrail_id is set."
  type        = string
  default     = "DRAFT"
}

# ── Memory ───────────────────────────────────────────────────────────────────

variable "enable_memory" {
  description = <<-EOT
    Enable Bedrock Agent Memory (SESSION_SUMMARY).
    When enabled, the agent summarises past sessions and uses them
    as context in future conversations. Requires Bedrock memory to be
    available in your region.
  EOT
  type        = bool
  default     = false
}

variable "memory_storage_days" {
  description = "How many days to retain agent memory (session summaries). Range: 1–365."
  type        = number
  default     = 30

  validation {
    condition     = var.memory_storage_days >= 1 && var.memory_storage_days <= 365
    error_message = "memory_storage_days must be between 1 and 365."
  }
}

# ── Agent Alias ───────────────────────────────────────────────────────────────

variable "create_agent_alias" {
  description = <<-EOT
    Whether to create an agent alias.
    An alias is required to invoke the agent from client applications.
    Creating an alias automatically pins a versioned snapshot of the agent.
  EOT
  type        = bool
  default     = true
}

variable "agent_alias_name" {
  description = "Name for the agent alias (e.g. 'prod', 'v1', 'live')."
  type        = string
  default     = "prod"
}

# ── Action Group ──────────────────────────────────────────────────────────────

variable "create_action_group" {
  description = <<-EOT
    Whether to create a Lambda-backed action group for the agent.
    When true, a Lambda function and its IAM role are also created.
    Set to false if you want an agent that responds from the model only
    (no tool use / external API calls).
  EOT
  type        = bool
  default     = true
}

# ── Lambda ────────────────────────────────────────────────────────────────────

variable "lambda_runtime" {
  description = "Lambda runtime for the action group handler."
  type        = string
  default     = "python3.12"

  validation {
    condition     = contains(["python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "lambda_runtime must be python3.10, python3.11, or python3.12."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds. Max: 900."
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB. Range: 128–10240."
  type        = number
  default     = 256
}

variable "lambda_env_vars" {
  description = "Environment variables to inject into the Lambda function."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for the Bedrock agent."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}
