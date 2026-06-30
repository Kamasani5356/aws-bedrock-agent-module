########################################################################
# outputs.tf — Exported values from the Bedrock Agent module
# Use these in other Terraform modules or to invoke the agent via SDK.
########################################################################

# ── Bedrock Agent ─────────────────────────────────────────────────────────────

output "agent_id" {
  description = "Unique ID of the Bedrock agent (e.g. GGRRAED6JP). Use with agent_alias_id to invoke the agent."
  value       = aws_bedrockagent_agent.this.agent_id
}

output "agent_arn" {
  description = "Full ARN of the Bedrock agent resource."
  value       = aws_bedrockagent_agent.this.agent_arn
}

output "agent_name" {
  description = "Full name of the Bedrock agent as created in AWS (name_prefix + agent_name)."
  value       = aws_bedrockagent_agent.this.agent_name
}

output "agent_version" {
  description = "Current version of the Bedrock agent (e.g. 'DRAFT' during development)."
  value       = aws_bedrockagent_agent.this.agent_version
}

output "agent_status" {
  description = "Lifecycle status of the Bedrock agent (CREATING | NOT_PREPARED | PREPARING | PREPARED | FAILED | DELETING)."
  value       = aws_bedrockagent_agent.this.agent_status
}

output "foundation_model" {
  description = "Foundation model ID the agent is configured to use."
  value       = aws_bedrockagent_agent.this.foundation_model
}

# ── Agent Alias ───────────────────────────────────────────────────────────────

output "agent_alias_id" {
  description = <<-EOT
    ID of the agent alias. Required for invoking the agent via SDK:
      client.invoke_agent(agentId=agent_id, agentAliasId=agent_alias_id, ...)
    Returns null if create_agent_alias = false.
  EOT
  value       = var.create_agent_alias ? aws_bedrockagent_agent_alias.this[0].agent_alias_id : null
}

output "agent_alias_arn" {
  description = "Full ARN of the agent alias. Returns null if create_agent_alias = false."
  value       = var.create_agent_alias ? aws_bedrockagent_agent_alias.this[0].agent_alias_arn : null
}

output "agent_alias_name" {
  description = "Name of the agent alias (e.g. 'prod'). Returns null if create_agent_alias = false."
  value       = var.create_agent_alias ? aws_bedrockagent_agent_alias.this[0].agent_alias_name : null
}

# ── Action Group ──────────────────────────────────────────────────────────────

output "action_group_id" {
  description = "ID of the Bedrock agent action group. Returns null if create_action_group = false."
  value       = var.create_action_group ? aws_bedrockagent_agent_action_group.this[0].action_group_id : null
}

# ── Lambda Function ───────────────────────────────────────────────────────────

output "lambda_function_arn" {
  description = "ARN of the action group Lambda function. Returns null if create_action_group = false."
  value       = var.create_action_group ? aws_lambda_function.agent_action[0].arn : null
}

output "lambda_function_name" {
  description = "Name of the action group Lambda function. Returns null if create_action_group = false."
  value       = var.create_action_group ? aws_lambda_function.agent_action[0].function_name : null
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "agent_role_arn" {
  description = "ARN of the IAM execution role used by the Bedrock agent."
  value       = aws_iam_role.bedrock_agent.arn
}

output "agent_role_name" {
  description = "Name of the IAM execution role used by the Bedrock agent."
  value       = aws_iam_role.bedrock_agent.name
}

# ── CloudWatch ────────────────────────────────────────────────────────────────

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Bedrock agent logs."
  value       = aws_cloudwatch_log_group.bedrock_agent.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group."
  value       = aws_cloudwatch_log_group.bedrock_agent.arn
}

# ── Invoke Helper ─────────────────────────────────────────────────────────────

output "invoke_command" {
  description = <<-EOT
    Example AWS CLI command to invoke the agent.
    Replace <SESSION_ID> with a unique session identifier for the conversation.
  EOT
  value = var.create_agent_alias ? (
    "aws bedrock-agent-runtime invoke-agent --agent-id ${aws_bedrockagent_agent.this.agent_id} --agent-alias-id ${aws_bedrockagent_agent_alias.this[0].agent_alias_id} --session-id <SESSION_ID> --input-text \"Hello!\""
  ) : "Create an alias first (set create_agent_alias = true)."
}

output "boto3_example" {
  description = "Example Python (boto3) snippet to invoke this agent programmatically."
  value       = <<-PYTHON
    import boto3, uuid

    client = boto3.client("bedrock-agent-runtime", region_name="${data.aws_region.current.name}")

    response = client.invoke_agent(
        agentId="${aws_bedrockagent_agent.this.agent_id}",
        agentAliasId="${var.create_agent_alias ? aws_bedrockagent_agent_alias.this[0].agent_alias_id : "<ALIAS_ID>"}",
        sessionId=str(uuid.uuid4()),
        inputText="What is today's date and time?",
    )

    for event in response["completion"]:
        if "chunk" in event:
            print(event["chunk"]["bytes"].decode("utf-8"), end="")
  PYTHON
}
