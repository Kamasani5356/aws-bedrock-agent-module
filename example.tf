########################################################################
# example.tf — Example usage of the Bedrock Agent Terraform module
#
# This file shows three usage patterns:
#   1. Minimal — fastest path to a working agent
#   2. Full-featured — all options enabled
#   3. Agent-only (no action group) — model-only responses
#
# Run:
#   terraform init
#   terraform plan -var-file="terraform.tfvars"
#   terraform apply -var-file="terraform.tfvars"
########################################################################

# ── Provider Configuration ────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "bedrock-agent-demo"
      ManagedBy = "terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region to deploy into. Bedrock is not available in all regions."
  type        = string
  default     = "us-east-1"
  # Other supported regions: us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-northeast-1
}

# ─────────────────────────────────────────────────────────────────────────────
# EXAMPLE 1: MINIMAL — Quickest working agent
# ─────────────────────────────────────────────────────────────────────────────

module "bedrock_agent_minimal" {
  source = "./"   # When using as a module, replace with: "git::https://github.com/your-org/terraform-bedrock-agent.git"

  name_prefix  = "myapp-dev"
  environment  = "dev"
  agent_name   = "support-bot"

  # Pick a foundation model (must have model access enabled in your account)
  foundation_model = "anthropic.claude-3-haiku-20240307-v1:0"

  # Instructions define the agent's behaviour — must be >= 40 chars
  agent_instruction = <<-EOT
    You are a friendly customer support assistant for an e-commerce platform.
    Help users track orders, answer product questions, and handle return requests.
    Always be polite and concise. Escalate complex issues to a human agent.
  EOT

  # Keep defaults for everything else:
  #   create_action_group = true  (Lambda + action group created automatically)
  #   create_agent_alias  = true  (alias "prod" created automatically)
  #   idle_session_ttl    = 1800  (30-minute sessions)
}

# Show the invoke command for the minimal agent after apply
output "minimal_agent_invoke_command" {
  description = "CLI command to test the minimal agent."
  value       = module.bedrock_agent_minimal.invoke_command
}

output "minimal_agent_id" {
  value = module.bedrock_agent_minimal.agent_id
}

output "minimal_alias_id" {
  value = module.bedrock_agent_minimal.agent_alias_id
}

# ─────────────────────────────────────────────────────────────────────────────
# EXAMPLE 2: FULL-FEATURED — All options enabled
# ─────────────────────────────────────────────────────────────────────────────

module "bedrock_agent_full" {
  source = "./"

  # ── Identity ──────────────────────────────────────────────────────────────
  name_prefix  = "myapp-prod"
  environment  = "prod"
  agent_name   = "enterprise-assistant"

  tags = {
    Team        = "platform-engineering"
    CostCenter  = "12345"
    Compliance  = "sox"
  }

  # ── Model ─────────────────────────────────────────────────────────────────
  # Claude 3.5 Sonnet — best quality for production workloads
  foundation_model = "anthropic.claude-3-5-sonnet-20241022-v2:0"

  agent_description = "Enterprise assistant: handles HR, IT, and Finance queries with RAG and tool use."

  agent_instruction = <<-EOT
    You are an enterprise assistant with access to HR, IT, and Finance tools.
    When a user asks about leave balances, salary slips, or benefits — use the HR action group.
    When a user asks about IT tickets or software access — use the IT action group.
    When a user asks about expense reports or invoices — use the Finance action group.
    Always greet the user by name if known. Be professional, concise, and accurate.
    If you cannot answer a question, say so and offer to connect the user with a human specialist.
  EOT

  # ── Session ───────────────────────────────────────────────────────────────
  idle_session_ttl_in_seconds = 3600   # 1 hour for production chatbots
  prepare_agent               = true

  # ── Action Group (Lambda) ─────────────────────────────────────────────────
  create_action_group = true
  lambda_runtime      = "python3.12"
  lambda_timeout      = 60
  lambda_memory_size  = 512
  lambda_env_vars = {
    LOG_LEVEL    = "INFO"
    API_ENDPOINT = "https://internal-api.mycompany.com"
    # Never put secrets here — use AWS Secrets Manager and read in Lambda
  }

  # ── Alias ─────────────────────────────────────────────────────────────────
  create_agent_alias = true
  agent_alias_name   = "v1"

  # ── Memory (optional) ─────────────────────────────────────────────────────
  # Enables session summary memory — agent remembers past conversations
  enable_memory       = true
  memory_storage_days = 14

  # ── Guardrail (optional) ──────────────────────────────────────────────────
  # Attach an existing Bedrock Guardrail (create one in the console first)
  # guardrail_id      = "abc123xyz"
  # guardrail_version = "1"
  guardrail_id      = null   # Set to your guardrail ID when ready
  guardrail_version = "DRAFT"

  # ── KMS Encryption (optional) ─────────────────────────────────────────────
  # kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/your-key-id"
  kms_key_arn = null

  # ── Observability ─────────────────────────────────────────────────────────
  log_retention_days = 90
}

output "full_agent_id" {
  description = "Agent ID for the full-featured agent."
  value       = module.bedrock_agent_full.agent_id
}

output "full_agent_alias_id" {
  description = "Alias ID for invoking the full-featured agent."
  value       = module.bedrock_agent_full.agent_alias_id
}

output "full_agent_boto3_example" {
  description = "Python snippet to invoke the full-featured agent."
  value       = module.bedrock_agent_full.boto3_example
}

# ─────────────────────────────────────────────────────────────────────────────
# EXAMPLE 3: AGENT-ONLY — No Lambda / no action group
# Use this when you want the model to answer purely from its own knowledge
# or from an externally-managed Knowledge Base.
# ─────────────────────────────────────────────────────────────────────────────

module "bedrock_agent_model_only" {
  source = "./"

  name_prefix  = "myapp-kb-agent"
  environment  = "dev"
  agent_name   = "knowledge-agent"

  foundation_model = "anthropic.claude-3-sonnet-20240229-v1:0"

  agent_instruction = <<-EOT
    You are a documentation assistant. Answer questions strictly based on the
    provided knowledge base. If the answer is not in the knowledge base, say
    "I don't have that information in my documentation."
    Do not make up answers or use external knowledge.
  EOT

  # Disable action group and Lambda — no tool use for this agent
  create_action_group = false
  create_agent_alias  = true
  agent_alias_name    = "docs"

  idle_session_ttl_in_seconds = 600   # 10 min for read-only Q&A bots
  log_retention_days          = 14
}

output "model_only_agent_id" {
  value = module.bedrock_agent_model_only.agent_id
}

output "model_only_alias_id" {
  value = module.bedrock_agent_model_only.agent_alias_id
}
