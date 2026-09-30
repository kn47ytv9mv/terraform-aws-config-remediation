resource "aws_config_remediation_configuration" "resource" {
  config_rule_name           = var.config_rule_name
  target_type                = "SSM_DOCUMENT"
  target_id                  = var.target_id
  target_version             = var.target_version
  resource_type              = var.resource_type
  automatic                  = var.automatic
  maximum_automatic_attempts = var.maximum_automatic_attempts
  retry_attempt_seconds      = var.retry_attempt_seconds

  dynamic "parameter" {
    for_each = var.automation_assume_role_arn[*]

    content {
      name         = "AutomationAssumeRole"
      static_value = parameter.value
    }
  }

  dynamic "parameter" {
    for_each = var.parameters

    content {
      name           = parameter.key
      static_value   = parameter.value.static_value
      static_values  = parameter.value.static_values
      resource_value = parameter.value.resource_value
    }
  }

  dynamic "execution_controls" {
    for_each = var.execution_controls[*]

    content {
      ssm_controls {
        concurrent_execution_rate_percentage = execution_controls.value.concurrent_execution_rate_percentage
        error_percentage                     = execution_controls.value.error_percentage
      }
    }
  }
}

output "id" {
  description = "The ID of the remediation configuration, which is the name of the rule it attaches to."
  value       = aws_config_remediation_configuration.resource.id
}

output "arn" {
  description = "The ARN of the remediation configuration."
  value       = aws_config_remediation_configuration.resource.arn
}
