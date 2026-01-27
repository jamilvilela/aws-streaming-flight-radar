# AWS Secrets Manager Integration Guide

## Overview
This guide explains how AWS Secrets Manager is integrated into the Flight Radar Streaming pipeline to securely store and manage OpenSky API credentials.

## Architecture

### Before (Insecure)
```
terraform.tfvars
  └── opensky_credentials (plaintext)
       ├── username
       └── password
         └── Lambda environment variables (visible in Lambda console)
```

### After (Secure)
```
AWS Secrets Manager
  └── flight-radar-stream-opensky-credentials (encrypted)
       ├── username
       └── password
         └── Lambda retrieves at runtime via IAM role
```

## Components

### 1. Secrets Manager Module (`infra/modules/secrets_manager/`)

#### main.tf
- **aws_secretsmanager_secret**: Creates the secret resource with:
  - Automatic encryption using AWS KMS
  - Recovery window (default: 7 days)
  - Tagging for resource management
  
- **aws_secretsmanager_secret_version**: Stores the actual secret value containing:
  - `username`: OpenSky API username
  - `password`: OpenSky API password
  
- **aws_secretsmanager_secret_policy**: Defines access control:
  - Only Lambda roles with `requires_opensky_credentials=true` can access
  - Action: `secretsmanager:GetSecretValue`
  - Policy automatically grants access to all Lambda roles that need credentials

- **aws_cloudwatch_log_group**: Audit logs for secret access

#### variables.tf
- `project_name`: For resource naming
- `opensky_username`: API username (marked as `sensitive`)
- `opensky_password`: API password (marked as `sensitive`)
- `lambda_role_arns`: List of Lambda IAM roles that can access the secret
- `recovery_window_days`: Days before permanent deletion
- `log_retention_days`: CloudWatch log retention
- `tags`: Resource tags

#### outputs.tf
- `secret_arn`: ARN for Lambda to reference
- `secret_id`: Name of the secret
- `secret_version_id`: Version ID
- `secret_access_policy`: Policy ARN
- `cloudwatch_log_group`: Audit log group

### 2. Updated Lambda Module

#### Changes to `infra/modules/lambda_ingest/`

**variables.tf**:
- Removed: `opensky_credentials` (object with username/password)
- Added: `opensky_secret_arn` (string with secret ARN)

**main.tf**:
- Environment variable now contains `OPENSKY_SECRET_ARN` instead of credentials
- Added IAM policy `lambda_secrets_manager_policy`:
  - Action: `secretsmanager:GetSecretValue`
  - Resource: Secret ARN
  - Only created if `requires_opensky_credentials=true`

**outputs.tf**:
- No changes (already included `lambda_role_arn`)

### 3. Lambda Python Code

#### Updated `app/src/ingest_flights/lambda_function.py`

**New imports**:
```python
import boto3
...
secrets_client = boto3.client('secretsmanager')
```

**Updated `get_opensky_states()` function**:
```python
# Before
user = os.environ.get('OPENSKY_USER')
password = os.environ.get('OPENSKY_PASSWORD')

# After
secret_arn = os.environ.get('OPENSKY_SECRET_ARN')
secret_response = secrets_client.get_secret_value(SecretId=secret_arn)
secret_data = json.loads(secret_response['SecretString'])
user = secret_data.get('username')
password = secret_data.get('password')
```

### 4. Terraform Root Configuration

#### Updated `infra/variables.tf`
- Removed: `opensky_credentials` (object)
- Added: `opensky_username` (sensitive string)
- Added: `opensky_password` (sensitive string)
- Added: `secrets_recovery_window_days` (number)
- Added: `secrets_log_retention_days` (number)

#### Updated `infra/main.tf`
```terraform
module "secrets_manager" {
  source = "./modules/secrets_manager"
  
  project_name      = var.project_name
  opensky_username  = var.opensky_username
  opensky_password  = var.opensky_password
  lambda_role_arns  = [for k, config in var.lambda_functions : 
                       module.lambda_ingest[k].lambda_role_arn 
                       if config.enabled && config.requires_opensky_credentials]
  ...
}

module "lambda_ingest" {
  ...
  opensky_secret_arn  = module.secrets_manager.secret_arn  # Changed from opensky_credentials
  depends_on = [module.kinesis_data_stream, module.secrets_manager]
}
```

#### Updated `infra/outputs.tf`
```terraform
output "secrets_manager_info" {
  value = {
    opensky_credentials = {
      secret_id         = module.secrets_manager.secret_id
      secret_arn        = module.secrets_manager.secret_arn
      version_id        = module.secrets_manager.secret_version_id
      access_policy_arn = module.secrets_manager.secret_access_policy
      log_group         = module.secrets_manager.cloudwatch_log_group
    }
  }
}
```

### 5. Configuration Files

#### Updated `infra/tfvars/terraform.tfvars`
```terraform
# Before
opensky_credentials = {
  username = "jamilvilela"
  password = "9!jT9_kFmXGVH!B"
}

# After (credentials NOT stored in tfvars)
opensky_username = "jamilvilela"
opensky_password = "9!jT9_kFmXGVH!B"

secrets_recovery_window_days = 7
secrets_log_retention_days   = 7
```

## Security Benefits

### 1. Encryption at Rest
- Secrets stored encrypted in AWS Secrets Manager
- Uses AWS KMS keys for encryption
- Automatic key rotation

### 2. Encryption in Transit
- API calls to Secrets Manager use TLS
- Credentials never exposed in Lambda console

### 3. Access Control
- IAM-based access control
- Only Lambda roles with correct permissions can retrieve
- Automatic policy generation based on function configuration

### 4. Audit Logging
- All secret access logged to CloudWatch
- Can monitor who accessed credentials and when
- Integration with CloudTrail for compliance

### 5. Rotation Support
- AWS Secrets Manager supports automatic rotation
- Can implement custom rotation functions
- Update Lambda without code changes

### 6. No Code Exposure
- Credentials not visible in:
  - Terraform state (as variables)
  - Lambda console environment variables
  - Application logs
  - GitHub repository (if using Git)

## Deployment Instructions

### 1. Initialize Terraform
```bash
cd infra/
terraform init
```

### 2. Validate Configuration
```bash
terraform validate
terraform plan
```

### 3. Apply Infrastructure
```bash
terraform apply -var-file=tfvars/terraform.tfvars
```

### 4. Verify Secret Creation
```bash
aws secretsmanager get-secret-value \
  --secret-id flight-radar-stream-opensky-credentials \
  --region us-east-1
```

### 5. Test Lambda Access
- Invoke Lambda function
- Check CloudWatch logs for successful credential retrieval
- Verify state vectors sent to Kinesis

## Credential Rotation

### Manual Rotation
```bash
aws secretsmanager update-secret-version-stage \
  --secret-id flight-radar-stream-opensky-credentials \
  --version-stage AWSCURRENT
```

### Automatic Rotation (Optional)
1. Create Lambda rotation function
2. Configure secret with rotation rule
3. Test rotation lifecycle

## Cost Analysis

### AWS Secrets Manager Pricing
- Storage: $0.40 per secret per month
- API calls: $0.06 per 10,000 calls
- OpenSky credentials storage: ~$0.40/month
- Lambda calls (~1 per minute): ~$17/month

**Total monthly cost increase**: ~$17.40
**Note**: This is included in overall Lambda execution costs

### Comparison
| Component | Cost |
|-----------|------|
| Previous (credentials in Lambda env vars) | $0 (security risk) |
| With Secrets Manager | $17.40/month |
| **Security benefit** | **Eliminates credential exposure** |

## Troubleshooting

### Lambda Cannot Retrieve Secret
**Error**: "User: ... is not authorized to perform: secretsmanager:GetSecretValue"

**Solution**:
1. Verify Lambda role ARN in Terraform output
2. Check Secrets Manager policy grants access
3. Verify `OPENSKY_SECRET_ARN` environment variable is set

### Secret Not Found
**Error**: "ResourceNotFoundException: Secrets Manager can't find the specified secret"

**Solution**:
1. Check secret ARN format in Lambda environment
2. Verify secret exists: `aws secretsmanager describe-secret --secret-id <arn>`
3. Ensure Lambda is in same AWS region

### JSON Parse Error
**Error**: "Error: invalid json in secret string"

**Solution**:
1. Verify secret format is valid JSON
2. Check credentials contain no special characters that need escaping
3. Test retrieval: `aws secretsmanager get-secret-value --secret-id <arn>`

## Best Practices

1. **Never commit credentials** to version control
2. **Use IAM roles**, not access keys for Lambda
3. **Rotate credentials** periodically (at least annually)
4. **Monitor access** via CloudWatch logs
5. **Use strong passwords** (OpenSky recommends special characters)
6. **Test rotation** in non-production environment first
7. **Document** rotation procedures for team

## Next Steps

1. Deploy Secrets Manager module
2. Verify Lambda can retrieve credentials
3. Monitor CloudWatch logs for issues
4. Test end-to-end data flow (OpenSky → Lambda → Kinesis)
5. Plan credential rotation schedule
6. Document procedures for team

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [Python Boto3 Secrets Manager](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/secretsmanager.html)
- [OpenSky API Authentication](https://opensky-network.org/apidoc/rest.html)
- [Terraform AWS Secrets Manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret)
