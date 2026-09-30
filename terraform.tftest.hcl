mock_provider "aws" {}

run "automation_assume_role_in_parameters_is_rejected" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
    parameters = {
      AutomationAssumeRole = { static_value = "arn:aws:iam::123456789012:role/config-remediation" }
    }
  }

  expect_failures = [var.parameters]
}

run "parameter_setting_two_value_kinds_is_rejected" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
    parameters = {
      BucketName = {
        static_value   = "example"
        resource_value = "RESOURCE_ID"
      }
    }
  }

  expect_failures = [var.parameters]
}

run "resource_value_other_than_resource_id_is_rejected" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
    parameters = {
      BucketName = { resource_value = "RESOURCE_ARN" }
    }
  }

  expect_failures = [var.parameters]
}

run "maximum_automatic_attempts_above_twenty_five_is_rejected" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-versioning-enabled"
    target_id                  = "AWS-ConfigureS3BucketVersioning"
    maximum_automatic_attempts = 26
  }

  expect_failures = [var.maximum_automatic_attempts]
}

run "retry_attempt_seconds_above_the_window_ceiling_is_rejected" {
  command = plan

  variables {
    config_rule_name      = "s3-bucket-versioning-enabled"
    target_id             = "AWS-ConfigureS3BucketVersioning"
    retry_attempt_seconds = 2678001
  }

  expect_failures = [var.retry_attempt_seconds]
}

run "execution_controls_percentage_above_one_hundred_is_rejected" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-versioning-enabled"
    target_id        = "AWS-ConfigureS3BucketVersioning"
    execution_controls = {
      concurrent_execution_rate_percentage = 101
    }
  }

  expect_failures = [var.execution_controls]
}

run "minimal_config_is_manual_and_renders_no_optional_blocks" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.target_type == "SSM_DOCUMENT"
    error_message = "target_type should always be 'SSM_DOCUMENT' — the only target type AWS Config accepts."
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.automatic == false
    error_message = "automatic should default to false, so AWS never changes a resource unprompted."
  }

  assert {
    condition     = length(aws_config_remediation_configuration.resource.parameter) == 0
    error_message = "No role and no parameters given should render no parameter blocks."
  }

  assert {
    condition     = length(aws_config_remediation_configuration.resource.execution_controls) == 0
    error_message = "No execution_controls given should render no execution_controls block."
  }
}

run "automation_assume_role_arn_renders_its_own_parameter" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-server-side-encryption-enabled"
    target_id                  = "AWS-EnableS3BucketEncryption"
    automation_assume_role_arn = "arn:aws:iam::123456789012:role/config-remediation"
  }

  assert {
    condition     = length(aws_config_remediation_configuration.resource.parameter) == 1
    error_message = "A role ARN alone should render exactly one parameter block."
  }

  assert {
    condition     = one(aws_config_remediation_configuration.resource.parameter).name == "AutomationAssumeRole"
    error_message = "The role ARN should be passed to the document as its AutomationAssumeRole parameter."
  }

  assert {
    condition     = one(aws_config_remediation_configuration.resource.parameter).static_value == "arn:aws:iam::123456789012:role/config-remediation"
    error_message = "The role ARN should be passed as a static value."
  }
}

run "parameters_render_alongside_the_role_parameter" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-versioning-enabled"
    target_id                  = "AWS-ConfigureS3BucketVersioning"
    automation_assume_role_arn = "arn:aws:iam::123456789012:role/config-remediation"
    parameters = {
      BucketName      = { resource_value = "RESOURCE_ID" }
      VersioningState = { static_value = "Enabled" }
    }
  }

  assert {
    condition     = length(aws_config_remediation_configuration.resource.parameter) == 3
    error_message = "Two parameters plus the role parameter should render three parameter blocks."
  }

  assert {
    condition     = one([for parameter in aws_config_remediation_configuration.resource.parameter : parameter if parameter.name == "BucketName"]).resource_value == "RESOURCE_ID"
    error_message = "A resource_value parameter should carry RESOURCE_ID so each non-compliant resource is substituted in turn."
  }

  assert {
    condition     = one([for parameter in aws_config_remediation_configuration.resource.parameter : parameter if parameter.name == "VersioningState"]).static_value == "Enabled"
    error_message = "A static_value parameter should pass through unchanged."
  }
}

run "static_values_parameter_renders_a_list" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
    parameters = {
      SSEAlgorithm = { static_values = ["AES256"] }
    }
  }

  assert {
    condition     = one(aws_config_remediation_configuration.resource.parameter).static_values == tolist(["AES256"])
    error_message = "A static_values parameter should pass its list through unchanged."
  }
}

run "automatic_remediation_carries_its_retry_budget" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-versioning-enabled"
    target_id                  = "AWS-ConfigureS3BucketVersioning"
    automatic                  = true
    maximum_automatic_attempts = 3
    retry_attempt_seconds      = 600
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.automatic == true
    error_message = "automatic should pass through unchanged."
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.maximum_automatic_attempts == 3
    error_message = "maximum_automatic_attempts should pass through unchanged."
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.retry_attempt_seconds == 600
    error_message = "retry_attempt_seconds should pass through unchanged."
  }
}

run "execution_controls_render_nested_ssm_controls" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-versioning-enabled"
    target_id        = "AWS-ConfigureS3BucketVersioning"
    execution_controls = {
      concurrent_execution_rate_percentage = 25
      error_percentage                     = 10
    }
  }

  assert {
    condition     = length(aws_config_remediation_configuration.resource.execution_controls) == 1
    error_message = "execution_controls given should render exactly one execution_controls block."
  }

  assert {
    condition     = one(one(aws_config_remediation_configuration.resource.execution_controls).ssm_controls).concurrent_execution_rate_percentage == 25
    error_message = "concurrent_execution_rate_percentage should reach the nested ssm_controls block unchanged."
  }

  assert {
    condition     = one(one(aws_config_remediation_configuration.resource.execution_controls).ssm_controls).error_percentage == 10
    error_message = "error_percentage should reach the nested ssm_controls block unchanged."
  }
}

run "target_version_and_resource_type_pass_through" {
  command = plan

  variables {
    config_rule_name = "s3-bucket-server-side-encryption-enabled"
    target_id        = "AWS-EnableS3BucketEncryption"
    target_version   = "1"
    resource_type    = "AWS::S3::Bucket"
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.target_version == "1"
    error_message = "target_version should pass through unchanged."
  }

  assert {
    condition     = aws_config_remediation_configuration.resource.resource_type == "AWS::S3::Bucket"
    error_message = "resource_type should pass through unchanged."
  }
}

run "readme_manual_remediation_example" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-server-side-encryption-enabled"
    target_id                  = "AWS-EnableS3BucketEncryption"
    automation_assume_role_arn = "arn:aws:iam::123456789012:role/config-remediation"
    parameters = {
      BucketName = { resource_value = "RESOURCE_ID" }
    }
  }
}

run "readme_automatic_remediation_example" {
  command = plan

  variables {
    config_rule_name           = "s3-bucket-versioning-enabled"
    target_id                  = "AWS-ConfigureS3BucketVersioning"
    automation_assume_role_arn = "arn:aws:iam::123456789012:role/config-remediation"
    automatic                  = true
    maximum_automatic_attempts = 3
    retry_attempt_seconds      = 600
    parameters = {
      BucketName      = { resource_value = "RESOURCE_ID" }
      VersioningState = { static_value = "Enabled" }
    }
    execution_controls = {
      concurrent_execution_rate_percentage = 25
      error_percentage                     = 10
    }
  }
}
