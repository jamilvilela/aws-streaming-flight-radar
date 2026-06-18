# ---------------------------------------------------------------------------
# dms-vpc-role (AWS-managed policy, required by DMS)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "dms_vpc" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_vpc_assume_role.json
  description        = "Default DMS VPC management role"
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# Additional EC2 permissions required by DMS for VPC management.
# The AWS-managed AmazonDMSVPCManagementRole may not cover all actions
# that DMS needs when creating network interfaces in the VPC.
resource "aws_iam_role_policy" "dms_vpc_ec2" {
  name   = "dms-vpc-ec2-permissions"
  role   = aws_iam_role.dms_vpc.name
  policy = data.aws_iam_policy_document.dms_vpc_ec2.json
}

# ---------------------------------------------------------------------------
# DMS CloudWatch Logs role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "dms_cloudwatch_logs" {
  name               = "${var.project_name}-dms-cw-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  description        = "DMS CloudWatch Logs role for ${var.project_name}"
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_cloudwatch_logs" {
  name   = "${var.project_name}-dms-cw-logs-policy"
  role   = aws_iam_role.dms_cloudwatch_logs.id
  policy = data.aws_iam_policy_document.dms_cloudwatch_logs.json
}

# ---------------------------------------------------------------------------
# DMS S3 access role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "dms_s3" {
  name               = "${var.project_name}-dms-s3-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  description        = "DMS S3 access role for ${var.project_name}"
  tags               = var.tags
}

resource "aws_iam_role_policy" "dms_s3" {
  name   = "${var.project_name}-dms-s3-policy"
  role   = aws_iam_role.dms_s3.id
  policy = data.aws_iam_policy_document.dms_s3_access.json
}
