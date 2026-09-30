variable "config_rule_name" {
  default     = null
  description = "Name of the AWS Config rule whose non-compliant resources this remediation repairs, such as terraform-aws-config-rule's name output. A rule holds at most one remediation configuration, so this name identifies the remediation as well as the rule."
}

variable "target_id" {
  default     = null
  description = "Name of the SSM Automation document that performs the fix, such as 'AWS-EnableS3BucketEncryption' or 'AWS-ConfigureS3BucketVersioning'. The document must already exist in this account and region, and whatever parameters it requires must be supplied through parameters."
}

variable "target_version" {
  default     = null
  description = "Version of the SSM Automation document to run. If null, AWS runs the document's default version, which moves as the document is revised."
}

variable "resource_type" {
  default     = null
  description = "Restricts remediation to a single resource type, such as 'AWS::S3::Bucket'. Worth setting when the rule evaluates several resource types but the document only knows how to repair one of them. If null, every non-compliant resource the rule reports is remediated."
}

variable "automation_assume_role_arn" {
  default     = null
  description = "ARN of the IAM role SSM Automation assumes to perform the fix, passed to the document as its AutomationAssumeRole parameter. Build it with terraform-aws-iam-role, trusting ssm.amazonaws.com and granting exactly the permissions the document needs. Nearly every document requires it, and when it is missing or underprivileged the remediation fails inside SSM rather than at apply time."
}

variable "parameters" {
  default     = {}
  description = "Parameters handed to the SSM Automation document, keyed by the document's own parameter names. Each entry sets exactly one of static_value (a literal), static_values (a literal list), or resource_value ('RESOURCE_ID', which substitutes the identifier of each non-compliant resource the rule reported). Supply AutomationAssumeRole through automation_assume_role_arn instead of here. AWS accepts at most 25 parameters in total."
  type = map(object({
    static_value   = optional(string)
    static_values  = optional(list(string))
    resource_value = optional(string)
  }))

  validation {
    condition     = !contains(keys(var.parameters), "AutomationAssumeRole")
    error_message = "AutomationAssumeRole belongs in automation_assume_role_arn, not in parameters, so that it cannot be declared twice."
  }

  validation {
    condition = alltrue([
      for parameter in var.parameters :
      length([for value in [parameter.static_value, parameter.static_values, parameter.resource_value] : value if value != null]) == 1
    ])
    error_message = "Every parameters entry must set exactly one of static_value, static_values, or resource_value."
  }

  validation {
    condition = alltrue([
      for parameter in var.parameters :
      parameter.resource_value == null || parameter.resource_value == "RESOURCE_ID"
    ])
    error_message = "resource_value accepts only 'RESOURCE_ID', the one dynamic value AWS Config substitutes per non-compliant resource."
  }
}

variable "automatic" {
  default     = false
  description = "Whether AWS Config runs the document itself as soon as a resource is reported non-compliant. False registers the remediation so an operator can run it on demand from the AWS Config console or API, without AWS ever changing a resource unprompted. True hands AWS standing permission to modify infrastructure Terraform also manages; read the README's Design section before enabling it."
}

variable "maximum_automatic_attempts" {
  default     = null
  description = "How many times automatic remediation may fail for one resource within retry_attempt_seconds before AWS Config records a remediation exception and stops retrying that resource. Accepts 1 through 25. If null, AWS's own default of 5 applies. Ignored while automatic is false."

  validation {
    condition     = var.maximum_automatic_attempts == null || (var.maximum_automatic_attempts >= 1 && var.maximum_automatic_attempts <= 25)
    error_message = "maximum_automatic_attempts must be between 1 and 25."
  }
}

variable "retry_attempt_seconds" {
  default     = null
  description = "Length of the window, in seconds, over which maximum_automatic_attempts failures are counted. Accepts 1 through 2678000, roughly 31 days. If null, AWS's own default of 60 applies. Ignored while automatic is false."

  validation {
    condition     = var.retry_attempt_seconds == null || (var.retry_attempt_seconds >= 1 && var.retry_attempt_seconds <= 2678000)
    error_message = "retry_attempt_seconds must be between 1 and 2678000."
  }
}

variable "execution_controls" {
  default     = null
  description = "Throttles how hard SSM works when a rule reports many non-compliant resources at once. concurrent_execution_rate_percentage caps the share of those resources remediated in parallel, and error_percentage stops the run once that share of executions has failed. Both accept 1 through 100. If null, AWS's own defaults of 10 percent concurrency and 50 percent errors apply."
  type = object({
    concurrent_execution_rate_percentage = optional(number)
    error_percentage                     = optional(number)
  })

  validation {
    condition = var.execution_controls == null || alltrue([
      for percentage in [var.execution_controls.concurrent_execution_rate_percentage, var.execution_controls.error_percentage] :
      percentage == null || (percentage >= 1 && percentage <= 100)
    ])
    error_message = "execution_controls percentages must each be between 1 and 100."
  }
}
