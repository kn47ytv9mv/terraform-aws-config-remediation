# terraform-aws-config-remediation

Terraform module for an AWS Config remediation configuration — the
action that actually repairs a resource an AWS Config rule reported as
non-compliant, by running an SSM Automation document against it.

## Cost

Creating and keeping a remediation configuration costs nothing. What
bills is the work it triggers: every remediation attempt is an SSM
Automation execution, and Systems Manager charges automation by the
step. A rule that reports hundreds of non-compliant resources produces
hundreds of executions, and automatic remediation retries a failing
resource up to `maximum_automatic_attempts` times, so a document that
cannot succeed still bills for each attempt before AWS Config gives up
on that resource. The rule's own evaluations bill separately. See AWS's
[Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/)
and [Config pricing](https://aws.amazon.com/config/pricing/) pages for
current rates.

## Design

AWS Config holds at most one remediation configuration per rule, keyed
on the rule's name, and this module creates exactly that one. It is
standalone rather than folded into
[`terraform-aws-config-rule`](https://github.com/kn47ytv9mv/terraform-aws-config-rule)
because
[`terraform-aws-config-baseline`](https://github.com/kn47ytv9mv/terraform-aws-config-baseline)
stands up a whole set of rules at once, and a caller needs to be able
to attach a remediation to any one of them by name. `config_rule_name`
is therefore free to be another module's output: nothing in this module
branches on its value, so the remediation plans cleanly in the same
apply that creates the rule it repairs.

`target_type` is fixed at `SSM_DOCUMENT` and is not exposed as an
input, because that is the only target type the AWS Config API accepts.
`target_id` names the document, such as `AWS-EnableS3BucketEncryption`
or `AWS-ConfigureS3BucketVersioning`; AWS owns a large catalog of them,
and a document from that catalog, a Systems Manager document shared
with the account, or one written in-house are all equally valid here so
long as the name resolves in the same account and region. The resource
supports no tags, so this module takes no `tags` variable.

### Automatic remediation changes infrastructure without asking

`automatic` defaults to `false`, which is the safe default rather than
the obvious one, and it is worth being clear about why. Automatic
remediation is a second actor with write access to resources Terraform
believes it owns. Non-compliance and drift are not the same thing: a
resource may be non-compliant because someone changed it by mistake, or
because a reviewed Terraform change has not been applied yet, or
because the account deliberately accepts that risk for that resource.
Automatic remediation cannot tell those cases apart. It sees a
non-compliant resource, rewrites it, and Terraform then reports the
resource as drifted at the next plan and rewrites it back. Two systems
each convinced they own the same attribute will push it back and forth
indefinitely.

Defaulting to `false` means adding this module changes nothing on its
own: the remediation is registered against the rule and an operator
runs it deliberately, per resource or per rule, from the AWS Config
console or the `StartRemediationExecution` API. That is the right shape
for adopting remediation against an existing account, where the first
run is as much an audit of the document as a fix.

Setting it to `true` is the point of the feature and is entirely
reasonable once the surrounding configuration agrees with it. Before
enabling it for a rule, make the Terraform configuration for the
attribute being remediated compliant in the first place, so that AWS
and Terraform want the same end state and the fight cannot start. Where
that is not possible — an attribute Terraform does not manage, or one
managed elsewhere — keep it out of Terraform's view with a `lifecycle`
block on the resource that owns it. Enable it one rule at a time rather
than across a baseline, and pair it with `execution_controls` below.

### The remediation role is not created here

Nearly every SSM Automation document takes an `AutomationAssumeRole`
parameter: the IAM role SSM assumes to make the change. This module
passes `automation_assume_role_arn` through as that parameter, but it
does not create the role — build it with
[`terraform-aws-iam-role`](https://github.com/kn47ytv9mv/terraform-aws-iam-role),
trusting `ssm.amazonaws.com` and granting exactly the actions the
chosen document performs.

Be aware of how this fails, because it fails quietly. A missing or
underprivileged role does not break `terraform apply` — the
remediation configuration is valid and AWS accepts it. The failure
surfaces only when a remediation runs: the execution fails inside
Systems Manager, the resource stays non-compliant, and the only record
is the remediation history in the AWS Config console. A remediation
that appears to do nothing is almost always this. Each document's own
documentation lists the parameters it requires and the permissions
those actions need.

### Throttling many non-compliant resources at once

A rule evaluated against an existing account commonly reports its
entire backlog of non-compliant resources in one pass, and every one of
them becomes a remediation execution. `execution_controls` caps the
share of those resources remediated in parallel, which keeps a broad
remediation from exhausting the API rate limits of whatever service it
is fixing, and stops the run once a given share of executions has
failed. That second control is the more valuable one: it means a
document that is wrong — bad parameters, insufficient permissions —
fails against a handful of resources instead of every one of them
before anybody notices.

## Usage

```hcl
module "encryption_remediation" {
  source = "kn47ytv9mv/config-remediation/aws"

  config_rule_name           = "s3-bucket-server-side-encryption-enabled"
  target_id                  = "AWS-EnableS3BucketEncryption"
  automation_assume_role_arn = "arn:aws:iam::123456789012:role/config-remediation"

  parameters = {
    BucketName = { resource_value = "RESOURCE_ID" }
  }
}
```

Or directly from this repository, attached to a rule this family
creates and left to run automatically under a concurrency cap:

```hcl
module "versioning_rule" {
  source = "kn47ytv9mv/config-rule/aws"

  name              = "s3-bucket-versioning-enabled"
  source_identifier = "S3_BUCKET_VERSIONING_ENABLED"
}

module "versioning_role" {
  source = "kn47ytv9mv/iam-role/aws"

  principal_identifiers = ["ssm.amazonaws.com"]

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutBucketVersioning"]
      Resource = "arn:aws:s3:::*"
    }]
  })
}

module "versioning_remediation" {
  source = "github.com/kn47ytv9mv/terraform-aws-config-remediation"

  config_rule_name           = module.versioning_rule.name
  target_id                  = "AWS-ConfigureS3BucketVersioning"
  automation_assume_role_arn = module.versioning_role.arn
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
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.3 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| config_rule_name | Name of the AWS Config rule whose non-compliant resources this remediation repairs, such as terraform-aws-config-rule's name output. A rule holds at most one remediation configuration, so this name identifies the remediation as well as the rule. | `null` | no |
| target_id | Name of the SSM Automation document that performs the fix, such as 'AWS-EnableS3BucketEncryption' or 'AWS-ConfigureS3BucketVersioning'. The document must already exist in this account and region, and whatever parameters it requires must be supplied through parameters. | `null` | no |
| target_version | Version of the SSM Automation document to run. If null, AWS runs the document's default version, which moves as the document is revised. | `null` | no |
| resource_type | Restricts remediation to a single resource type, such as 'AWS::S3::Bucket'. Worth setting when the rule evaluates several resource types but the document only knows how to repair one of them. If null, every non-compliant resource the rule reports is remediated. | `null` | no |
| automation_assume_role_arn | ARN of the IAM role SSM Automation assumes to perform the fix, passed to the document as its AutomationAssumeRole parameter. Build it with terraform-aws-iam-role, trusting ssm.amazonaws.com and granting exactly the permissions the document needs. Nearly every document requires it, and when it is missing or underprivileged the remediation fails inside SSM rather than at apply time. | `null` | no |
| parameters | Parameters handed to the SSM Automation document, keyed by the document's own parameter names. Each entry sets exactly one of static_value (a literal), static_values (a literal list), or resource_value ('RESOURCE_ID', which substitutes the identifier of each non-compliant resource the rule reported). Supply AutomationAssumeRole through automation_assume_role_arn instead of here. AWS accepts at most 25 parameters in total. | `{}` | no |
| automatic | Whether AWS Config runs the document itself as soon as a resource is reported non-compliant. False registers the remediation so an operator can run it on demand from the AWS Config console or API, without AWS ever changing a resource unprompted. True hands AWS standing permission to modify infrastructure Terraform also manages; read the README's Design section before enabling it. | `false` | no |
| maximum_automatic_attempts | How many times automatic remediation may fail for one resource within retry_attempt_seconds before AWS Config records a remediation exception and stops retrying that resource. Accepts 1 through 25. If null, AWS's own default of 5 applies. Ignored while automatic is false. | `null` | no |
| retry_attempt_seconds | Length of the window, in seconds, over which maximum_automatic_attempts failures are counted. Accepts 1 through 2678000, roughly 31 days. If null, AWS's own default of 60 applies. Ignored while automatic is false. | `null` | no |
| execution_controls | Throttles how hard SSM works when a rule reports many non-compliant resources at once. concurrent_execution_rate_percentage caps the share of those resources remediated in parallel, and error_percentage stops the run once that share of executions has failed. Both accept 1 through 100. If null, AWS's own defaults of 10 percent concurrency and 50 percent errors apply. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the remediation configuration, which is the name of the rule it attaches to. |
| arn | The ARN of the remediation configuration. |

## License

MIT — see [LICENSE.md](LICENSE.md).
