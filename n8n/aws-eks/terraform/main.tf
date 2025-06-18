terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  
  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      Project     = "n8n-scalable"
      ManagedBy   = "Terraform"
    })
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Configuration
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS specific tags
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Cluster endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Node groups
  eks_managed_node_groups = {
    n8n_main = {
      name = "n8n-main"
      
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      
      min_size     = 2
      max_size     = 4
      desired_size = 2
      
      labels = {
        Environment = var.environment
        NodeGroup   = "n8n-main"
        Role        = "main"
      }
      
      taints = [
        {
          key    = "n8n.io/main"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    
    n8n_worker = {
      name = "n8n-worker"
      
      instance_types = ["t3.xlarge", "t3a.xlarge"]
      capacity_type  = "SPOT"
      
      min_size     = 2
      max_size     = 20
      desired_size = 3
      
      labels = {
        Environment = var.environment
        NodeGroup   = "n8n-worker"
        Role        = "worker"
      }
      
      taints = [
        {
          key    = "n8n.io/worker"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    
    n8n_infra = {
      name = "n8n-infra"
      
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      
      min_size     = 2
      max_size     = 4
      desired_size = 2
      
      labels = {
        Environment = var.environment
        NodeGroup   = "n8n-infra"
        Role        = "infrastructure"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = module.eks_admins_iam_role.iam_role_arn
      username = "eks-admin"
      groups   = ["system:masters"]
    }
  ]

  tags = {
    Environment = var.environment
  }
}

# IAM role for EKS administrators
module "eks_admins_iam_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-eks-admin"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:eks-admin"]
    }
  }

  tags = {
    Environment = var.environment
  }
}

# ElastiCache Redis for n8n queue and streams
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-redis"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.cluster_name}-redis"
  description                = "Redis cluster for n8n queue and streams"
  
  node_type                  = var.redis_node_type
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  subnet_group_name = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  # Stream configuration
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  tags = {
    Name = "${var.cluster_name}-redis"
  }
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/aws/elasticache/redis/${var.cluster_name}"
  retention_in_days = 30
}

# RDS PostgreSQL for n8n database
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.cluster_name}-postgres"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}

resource "aws_security_group" "postgres" {
  name_prefix = "${var.cluster_name}-postgres"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}

resource "random_password" "postgres_password" {
  length  = 16
  special = true
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.cluster_name}-postgres"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  engine         = "postgres"
  engine_version = "15.8"
  instance_class = var.postgres_instance_class

  db_name  = "n8n"
  username = "n8n"
  password = random_password.postgres_password.result

  vpc_security_group_ids = [aws_security_group.postgres.id]
  db_subnet_group_name   = aws_db_subnet_group.postgres.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Sun:04:00-Sun:05:00"

  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.cluster_name}-postgres-final-snapshot" : null

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}

# Secrets Manager for sensitive data
resource "aws_secretsmanager_secret" "n8n_secrets" {
  name        = "${var.cluster_name}-n8n-secrets"
  description = "Secrets for n8n deployment"

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "n8n_secrets" {
  secret_id = aws_secretsmanager_secret.n8n_secrets.id
  secret_string = jsonencode({
    N8N_ENCRYPTION_KEY      = random_password.n8n_encryption_key.result
    DB_POSTGRESDB_PASSWORD  = random_password.postgres_password.result
    N8N_BASIC_AUTH_PASSWORD = random_password.n8n_auth_password.result
  })
}

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

resource "random_password" "n8n_auth_password" {
  length  = 16
  special = true
}

# ALB Ingress Controller IAM role
module "load_balancer_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-load-balancer-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Environment = var.environment
  }
}

# External Secrets Operator IAM role
module "external_secrets_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets-system:external-secrets"]
    }
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "external_secrets_policy" {
  name = "${var.cluster_name}-external-secrets-policy"
  role = module.external_secrets_irsa_role.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.n8n_secrets.arn
      }
    ]
  })
}

# EBS CSI Driver IAM role
module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Environment = var.environment
  }
} 