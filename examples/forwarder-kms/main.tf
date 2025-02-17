locals {
  name        = basename(abspath(path.root))
  name_prefix = "${local.name}-"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "kms_default_key_policy" {
  statement {
    actions = [
      "kms:*",
    ]
    principals {
      identifiers = [
        "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
      type = "AWS"
    }
    resources = [
      "*",
    ]
    sid = "Enable IAM User Permissions"
  }
}

resource "aws_kms_key" "source" {
  policy = data.aws_iam_policy_document.kms_default_key_policy.json
}

resource "aws_s3_bucket" "source" {
  bucket_prefix = "${local.name_prefix}-source"
  force_destroy = true
}

resource "aws_s3_bucket" "destination" {
  bucket_prefix = "${local.name_prefix}-destination"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.source.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_notification" "source" {
  bucket      = aws_s3_bucket.source.id
  eventbridge = true
}

data "observe_workspace" "default" {
  name = "Default"
}

resource "observe_datastream" "this" {
  workspace = data.observe_workspace.default.oid
  name      = local.name
}

resource "observe_filedrop" "this" {
  workspace  = data.observe_workspace.default.oid
  datastream = observe_datastream.this.oid

  config {
    provider {
      aws {
        region   = "us-west-2"
        role_arn = "arn:${data.aws_partition.current.id}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}"
      }
    }
  }
}

module "forwarder" {
  # Prefer using the hashicorp registry:
  # source = "observeinc/collection/aws//modules/forwarder"
  # For validation purposes we will instead refer to a local version of the
  # module:
  source = "../..//modules/forwarder"

  name                = local.name
  destination         = observe_filedrop.this.endpoint[0].s3[0]
  source_bucket_names = [aws_s3_bucket.source.bucket]
  source_kms_key_arns = [aws_kms_key.source.arn]
}
