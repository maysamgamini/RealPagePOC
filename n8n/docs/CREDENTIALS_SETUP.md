# Credentials Setup Guide

This guide explains how to configure your AWS and Azure credentials for Terraform deployments.

## AWS Credentials Setup

### Option 1: AWS CLI Configuration (Recommended)

1. **Install AWS CLI**
   ```bash
   # Windows (using chocolatey)
   choco install awscli
   
   # macOS (using homebrew)
   brew install awscli
   
   # Linux (using pip)
   pip install awscli
   ```

2. **Configure AWS CLI**
   ```bash
   aws configure
   ```
   You'll be prompted for:
   - **AWS Access Key ID**: Your access key
   - **AWS Secret Access Key**: Your secret key
   - **Default region name**: e.g., `us-west-2`
   - **Default output format**: `json`

3. **Verify Configuration**
   ```bash
   aws sts get-caller-identity
   ```

### Option 2: Environment Variables

Set environment variables in your shell or `.env` file:

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="us-west-2"
```

For Windows PowerShell:
```powershell
$env:AWS_ACCESS_KEY_ID="your-access-key-id"
$env:AWS_SECRET_ACCESS_KEY="your-secret-access-key"
$env:AWS_DEFAULT_REGION="us-west-2"
```

### Option 3: AWS Credentials File

Create/edit `~/.aws/credentials`:
```ini
[default]
aws_access_key_id = your-access-key-id
aws_secret_access_key = your-secret-access-key

[production]
aws_access_key_id = your-prod-access-key
aws_secret_access_key = your-prod-secret-key
```

Create/edit `~/.aws/config`:
```ini
[default]
region = us-west-2
output = json

[profile production]
region = us-east-1
output = json
```

### Using AWS Profiles

To use a specific profile with Terraform:

1. **Set environment variable**:
   ```bash
   export AWS_PROFILE=production
   ```

2. **Or update terraform.tfvars**:
   ```hcl
   aws_profile = "production"
   ```

### Getting AWS Access Keys

1. **Go to AWS Console** → IAM → Users
2. **Select your user** → Security credentials
3. **Create access key** → Command Line Interface (CLI)
4. **Download** the credentials CSV file
5. **Store securely** and delete the CSV file

### Required AWS Permissions

Your AWS user/role needs these permissions:
- EC2 full access
- EKS full access
- IAM full access
- VPC full access
- ElastiCache full access
- RDS full access
- Secrets Manager full access

## Azure Credentials Setup

### Option 1: Azure CLI (Recommended)

1. **Install Azure CLI**
   ```bash
   # Windows (using chocolatey)
   choco install azure-cli
   
   # macOS (using homebrew)
   brew install azure-cli
   
   # Linux (using curl)
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

2. **Login to Azure**
   ```bash
   az login
   ```
   This will open a browser for authentication.

3. **Set subscription (if you have multiple)**
   ```bash
   az account set --subscription "your-subscription-id"
   ```

4. **Verify configuration**
   ```bash
   az account show
   ```

### Option 2: Service Principal (Production)

1. **Create Service Principal**
   ```bash
   az ad sp create-for-rbac --name "n8n-terraform" --role="Contributor" --scopes="/subscriptions/your-subscription-id"
   ```

2. **Save the output**:
   ```json
   {
     "appId": "your-client-id",
     "displayName": "n8n-terraform",
     "password": "your-client-secret",
     "tenant": "your-tenant-id"
   }
   ```

3. **Set environment variables**:
   ```bash
   export ARM_CLIENT_ID="your-client-id"
   export ARM_CLIENT_SECRET="your-client-secret"
   export ARM_SUBSCRIPTION_ID="your-subscription-id"
   export ARM_TENANT_ID="your-tenant-id"
   ```

   For Windows PowerShell:
   ```powershell
   $env:ARM_CLIENT_ID="your-client-id"
   $env:ARM_CLIENT_SECRET="your-client-secret"
   $env:ARM_SUBSCRIPTION_ID="your-subscription-id"
   $env:ARM_TENANT_ID="your-tenant-id"
   ```

### Option 3: Terraform Variables File

1. **Copy the example file**:
   ```bash
   cp azure-aks/terraform/terraform.tfvars.example azure-aks/terraform/terraform.tfvars
   ```

2. **Edit terraform.tfvars**:
   ```hcl
   azure_subscription_id = "your-subscription-id"
   azure_tenant_id       = "your-tenant-id"
   azure_client_id       = "your-client-id"
   azure_client_secret   = "your-client-secret"
   ```

### Getting Azure IDs

1. **Subscription ID**:
   ```bash
   az account show --query id --output tsv
   ```

2. **Tenant ID**:
   ```bash
   az account show --query tenantId --output tsv
   ```

3. **Client ID & Secret**: From service principal creation above

### Required Azure Permissions

Your service principal needs these roles:
- Contributor (for resource management)
- User Access Administrator (for role assignments)

## Deployment Instructions

### AWS EKS Deployment

1. **Set up credentials** (choose one method above)

2. **Configure terraform.tfvars**:
   ```bash
   cd aws-eks/terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Azure AKS Deployment

1. **Set up credentials** (choose one method above)

2. **Configure terraform.tfvars**:
   ```bash
   cd azure-aks/terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Security Best Practices

### AWS Security

1. **Use IAM roles** when possible (for EC2 instances)
2. **Rotate access keys** regularly
3. **Use least privilege** permissions
4. **Enable MFA** on your AWS account
5. **Never commit** credentials to version control

### Azure Security

1. **Use managed identities** when possible
2. **Rotate service principal secrets** regularly
3. **Use Azure Key Vault** for production secrets
4. **Enable MFA** on your Azure account
5. **Use Azure AD Conditional Access**

### General Security

1. **Use .gitignore** to exclude credential files:
   ```gitignore
   # Terraform
   *.tfvars
   *.tfstate
   *.tfstate.backup
   .terraform/
   
   # AWS
   .aws/
   
   # Environment variables
   .env
   .env.local
   ```

2. **Use environment-specific credentials**
3. **Monitor credential usage** with CloudTrail (AWS) or Activity Log (Azure)
4. **Implement credential scanning** in CI/CD pipelines

## Troubleshooting

### Common AWS Issues

1. **"Access Denied"**: Check IAM permissions
2. **"Region not supported"**: Verify region availability
3. **"Credential not found"**: Check AWS CLI configuration

### Common Azure Issues

1. **"Authentication failed"**: Re-run `az login`
2. **"Subscription not found"**: Check subscription ID
3. **"Insufficient privileges"**: Verify service principal roles

### Debug Commands

```bash
# AWS
aws sts get-caller-identity
aws configure list

# Azure
az account show
az ad signed-in-user show

# Terraform
terraform providers
terraform version
```

## Next Steps

After setting up credentials:

1. **Test with a simple deployment**
2. **Set up monitoring and alerting**
3. **Configure backup strategies**
4. **Implement infrastructure as code best practices**
5. **Set up CI/CD pipelines**

For deployment instructions, see [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md). 