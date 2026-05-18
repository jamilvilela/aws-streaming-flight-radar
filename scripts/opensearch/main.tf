# =============================================================================
# OPENSEARCH SERVERLESS COLLECTION
# =============================================================================

resource "aws_opensearchserverless_collection" "flights" {
  name     = var.collection_name
  type     = var.collection_type
  standby_replicas = var.standby_replicas

  description = "Collection para dados de voos - ${var.project_name} (${var.environment})"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.collection_name}"
  })

  depends_on = [
    aws_opensearchserverless_security_policy.encryption
  ]
}

# =============================================================================
# ENCRYPTION POLICY 
# =============================================================================

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.collection_name}-encr-policy"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${var.collection_name}"]
    }]
    AWSOwnedKey = true  # Usa chave KMS gerenciada pela AWS
  })
}

# =============================================================================
# NETWORK POLICY 
# =============================================================================

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.collection_name}-netw-policy"
  type = "network"

  # Se VPC especificado, restringe acesso à VPC; caso contrário, permite público
  policy = var.vpc_id != "" ? jsonencode([
    {
      Rules = [{
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
      }]
      AllowFromPublic = false
      SourceVPCEs     = [var.vpc_id]
    }
  ]) : jsonencode([
    {
      Rules = [{
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
      }]
      AllowFromPublic = true
    }
  ])
}

# =============================================================================
# DATA ACCESS POLICY 
# =============================================================================

resource "aws_opensearchserverless_access_policy" "flights_access" {
  name = "${var.collection_name}-accs-policy"
  type = "data"  # Apenas data access (não inclui dashboard)

  policy = jsonencode([
    # ================================================================
    # REGRA 1: Firehose - Acesso à Collection
    # ================================================================
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.collection_name}"]
          Permission   = [
            "aoss:DescribeCollectionItems",
            "aoss:CreateCollectionItems",
            "aoss:UpdateCollectionItems"
          ]
        }
      ]
      Principal = [var.firehose_role_arn]
      Description = "Firehose collection access"
    },
    # ================================================================
    # REGRA 2: Firehose - Acesso aos Índices
    # ================================================================
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${var.collection_name}/*"]
          Permission   = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:WriteDocument",
            "aoss:ReadDocument",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex" 
          ]
        }
      ]
      Principal = [var.firehose_role_arn]
      Description = "Firehose index access"
    },
    # ================================================================
    # REGRA 3: Admin Users - Acesso à Collection
    # ================================================================
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.collection_name}"]
          Permission   = [
            "aoss:DescribeCollectionItems"
          ]
        }
      ]
      Principal   = var.dash_user_arns
      Description = "Admin dashboard and index access"
    },
    # ================================================================
    # REGRA 4: Admin Users - Acesso aos Índices
    # ================================================================
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${var.collection_name}/*"]
          Permission   = [
            "aoss:ReadDocument",
            "aoss:WriteDocument",
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex"
          ]
        }
      ]
      Principal = var.dash_user_arns
      Description = "Admin index access"
    }
  ])

  depends_on = [
    aws_opensearchserverless_collection.flights
  ]
}

# =============================================================================
# LIFECYCLE POLICY 
# =============================================================================

resource "aws_opensearchserverless_lifecycle_policy" "flights" {
  name = "${var.collection_name}-lfcy-policy"
  type = "retention"

  description = "Lifecycle policy for ${var.collection_name} retention"

  policy = jsonencode({
    Rules = [{
      ResourceType = "index"
      Resource     = ["index/${var.collection_name}/*"]
      MinIndexRetention = "30d"  # Retém dados por mínimo 30 dias
      
    }]
  })

  depends_on = [
    aws_opensearchserverless_collection.flights
  ]
}
