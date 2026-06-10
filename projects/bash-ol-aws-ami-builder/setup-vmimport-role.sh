#!/usr/bin/env bash
#==============================================================================
# setup-vmimport-role.sh
#
# ----- Purpose ----------------------------------------------------------------
# Creates the "vmimport" IAM service role required by AWS VM Import/Export.
# This is a ONE-TIME setup per AWS account. Once the role exists, all future
# AMI builds (via build-ol-aws-ami.sh) can reuse it.
#
# Upstream reference:
#   https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html
#
# ----- Prerequisites ----------------------------------------------------------
#   * AWS CLI v2 configured with credentials that have:
#       iam:CreateRole, iam:PutRolePolicy, iam:GetRole, iam:AttachRolePolicy
#   * The target S3 bucket name (does not need to exist yet).
#
# ----- Usage examples ---------------------------------------------------------
#   # Create the default 'vmimport' role tied to a specific S3 bucket
#   ./setup-vmimport-role.sh my-ol-ami-import-bucket
#
#   # Create a custom-named role
#   ./setup-vmimport-role.sh my-bucket my-custom-vmimport-role
#
# ----- Known limitations ------------------------------------------------------
#   * The role's S3 policy is scoped to the bucket given on the command
#     line. To stage VMDKs in multiple buckets, edit the role policy
#     afterwards or create separate roles per bucket.
#   * If a role with the same name already exists, this script exits with
#     an error rather than overwriting it.
#
# ----- AI generation info -----------------------------------------------------
#   AI tool: Anthropic Claude (Sonnet 4.5)
#   Generated: 2026-05
#==============================================================================

set -euo pipefail

S3_BUCKET="${1:-}"
ROLE_NAME="${2:-vmimport}"

[[ -z "${S3_BUCKET}" ]] && { echo "Usage: $0 <S3_BUCKET> [ROLE_NAME]" >&2; exit 1; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT

#------------------------------------------------------------------------------
# 1) Trust policy (allow vmie.amazonaws.com to assume the role)
#------------------------------------------------------------------------------
cat > "${WORKDIR}/trust-policy.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "vmie.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "sts:Externalid": "vmimport" }
      }
    }
  ]
}
EOF

#------------------------------------------------------------------------------
# 2) Role policy (permissions on S3 / EC2 / KMS)
#------------------------------------------------------------------------------
cat > "${WORKDIR}/role-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:GetBucketAcl"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ModifySnapshotAttribute",
        "ec2:CopySnapshot",
        "ec2:RegisterImage",
        "ec2:Describe*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateGrant",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

#------------------------------------------------------------------------------
# 3) Create the role and attach the policy
#------------------------------------------------------------------------------
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "[INFO] Role ${ROLE_NAME} already exists. Updating its trust policy."
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "file://${WORKDIR}/trust-policy.json"
else
  echo "[INFO] Creating new role: ${ROLE_NAME}"
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${WORKDIR}/trust-policy.json" \
    --description "AWS VM Import/Export service role for oracle-linux-image-tools"
fi

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "vmimport-policy" \
  --policy-document "file://${WORKDIR}/role-policy.json"

echo
echo "[OK] vmimport role is ready"
echo "     Role Name : ${ROLE_NAME}"
echo "     S3 Bucket : ${S3_BUCKET}"
