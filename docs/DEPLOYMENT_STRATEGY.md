# 📋 Estratégia de Deployment: Local vs Produção

## 🎯 3 Cenários de Deploy

### 1️⃣ **DESENVOLVIMENTO LOCAL** (Sua máquina)
```bash
bash deploy_flink_sql.sh start
```
✅ Rápido para testes  
✅ Controle manual  
❌ Não é seguro para produção  
❌ Requer AWS CLI local  
❌ Difícil de auditar

---

### 2️⃣ **PRODUÇÃO COM TERRAFORM** (Recomendado)
Terraform gerencia tudo:
- Criação dos streams
- Criação da aplicação Flink
- **INICIAR a aplicação automaticamente**
- Snapshots e backups
- Tudo com controle de versão Git

✅ Reproduzível  
✅ Seguro (credentials via CI/CD)  
✅ Auditável (tudo em Git)  
✅ Nenhum comando manual em produção  

---

### 3️⃣ **CI/CD PIPELINE** (GitHub Actions/GitLab CI)
Developer faz `git push` → Pipeline automático:
1. Valida Terraform
2. Cria/atualiza infraestrutura
3. Inicia aplicação Flink
4. Testa data flow
5. Notifica resultado

✅ Zero intervenção manual  
✅ Histórico completo  
✅ Rollback automático  
✅ Segregação de ambientes

---

## 🏗️ Arquitetura Recomendada

```
┌─────────────────────────────────────────────────────────────┐
│ DEVELOPER LOCAL (sua máquina)                               │
├─────────────────────────────────────────────────────────────┤
│ • Edita código Python, SQL, Terraform                       │
│ • Testa localmente (docker-compose, mock AWS)              │
│ • git commit + git push                                     │
└─────────────────────────────────────────────────────────────┘
                          ↓ push
┌─────────────────────────────────────────────────────────────┐
│ GITHUB ACTIONS (CI/CD Automation)                           │
├─────────────────────────────────────────────────────────────┤
│ 1. Valida Terraform                                         │
│ 2. Aplica Terraform (cria/atualiza recursos)                │
│ 3. Inicia Flink (via Terraform resource)                    │
│ 4. Testa data flow (boto3 script)                           │
│ 5. Notifica Slack/Email                                     │
└─────────────────────────────────────────────────────────────┘
              ↓ terraform apply
┌─────────────────────────────────────────────────────────────┐
│ AWS CLOUD (Infraestrutura em Produção)                      │
├─────────────────────────────────────────────────────────────┤
│ • Kinesis Streams                                            │
│ • KDA Flink Application (RUNNING)                           │
│ • Redshift Cluster                                          │
│ • CloudWatch Monitoring                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Opção 1: Terraform para Iniciar Flink

### ✅ Vantagens
- Tudo em código
- Seguro (credentials no CI/CD)
- Reproduzível
- Sem comandos manuais
- Integra com GitHub Actions

### Terraform Resource: `aws_kinesisanalyticsv2_application_start`

```hcl
# infra/modules/kda_flights/main.tf

# ============================================================================
# Recurso KDA (já criado)
# ============================================================================
resource "aws_kinesisanalyticsv2_application" "flight_radar_flink" {
  # ... configuração existente ...
}

# ============================================================================
# NOVO: Auto-start da aplicação
# ============================================================================
resource "aws_kinesisanalyticsv2_application_start" "flight_radar_flink" {
  application_name = aws_kinesisanalyticsv2_application.flight_radar_flink.name

  # Executar se auto_start = true nas variables
  count = var.auto_start_application ? 1 : 0

  # Depender de aplicação criada
  depends_on = [aws_kinesisanalyticsv2_application.flight_radar_flink]
}

# ============================================================================
# NOVO: Snapshots automáticos (backup)
# ============================================================================
resource "aws_kinesisanalyticsv2_application_snapshot" "flight_radar_backup" {
  application_name       = aws_kinesisanalyticsv2_application.flight_radar_flink.name
  snapshot_name          = "flink-backup-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  depends_on = [aws_kinesisanalyticsv2_application_start.flight_radar_flink]
}
```

### Variables.tf (Adicionar)

```hcl
variable "auto_start_application" {
  description = "Auto-start Flink application após criar"
  type        = bool
  default     = false  # false em dev, true em produção
}

variable "environment" {
  description = "Ambiente: dev, staging, prod"
  type        = string
  default     = "dev"
}
```

### terraform.tfvars

```hcl
# DESENVOLVIMENTO
# auto_start_application = false

# PRODUÇÃO (via CI/CD)
# auto_start_application = true
# environment = "prod"
```

---

## 📦 Opção 2: GitHub Actions Pipeline

### Arquivo: `.github/workflows/deploy-flink.yml`

```yaml
name: Deploy Flink SQL Application

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'infra/**'
      - 'app/flink-sql-application/**'
      - '.github/workflows/deploy-flink.yml'

env:
  AWS_REGION: us-east-1
  TF_VERSION: 1.6.0

jobs:
  validate:
    name: Validate Terraform & SQL
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Terraform Format Check
        run: terraform fmt -check -recursive infra/
      
      - name: Terraform Init
        run: cd infra && terraform init
      
      - name: Terraform Validate
        run: cd infra && terraform validate
      
      - name: Validate SQL Files
        run: |
          for file in app/flink-sql-application/{01,02,03}_*.sql; do
            if [ ! -f "$file" ]; then
              echo "✗ Arquivo SQL faltando: $file"
              exit 1
            fi
            echo "✓ Validado: $file"
          done

  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Terraform Init
        run: cd infra && terraform init
      
      - name: Terraform Plan
        run: |
          cd infra
          terraform plan \
            -var="auto_start_application=${{ github.ref == 'refs/heads/main' }}" \
            -var="environment=${{ github.ref == 'refs/heads/main' && 'prod' || 'staging' }}" \
            -out=tfplan
      
      - name: Upload Plan
        uses: actions/upload-artifact@v3
        with:
          name: tfplan
          path: infra/tfplan

  apply:
    name: Terraform Apply
    runs-on: ubuntu-latest
    needs: plan
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      
      - name: Download Plan
        uses: actions/download-artifact@v3
        with:
          name: tfplan
          path: infra/
      
      - name: Terraform Apply
        run: cd infra && terraform apply -auto-approve tfplan
      
      - name: Wait for Application
        run: |
          echo "⏳ Aguardando Flink iniciar..."
          for i in {1..30}; do
            STATUS=$(aws kinesisanalyticsv2 describe-application \
              --application-name flight-radar-kda-flights \
              --query 'ApplicationDetail.ApplicationStatus' \
              --output text)
            
            if [ "$STATUS" == "RUNNING" ]; then
              echo "✓ Flink está RUNNING"
              exit 0
            fi
            echo "Status: $STATUS (tentativa $i/30)"
            sleep 10
          done
          echo "✗ Timeout aguardando Flink"
          exit 1

  test:
    name: Test Data Flow
    runs-on: ubuntu-latest
    needs: apply
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Dependencies
        run: |
          pip install boto3
      
      - name: Test Data Flow
        run: python scripts/test_flink_pipeline.py
      
      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1
        with:
          webhook-url: ${{ secrets.SLACK_WEBHOOK }}
          payload: |
            {
              "text": "✓ Flink deployment concluído com sucesso",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Flink SQL Application Deployed*\n• Branch: ${{ github.ref }}\n• Commit: ${{ github.sha }}"
                  }
                }
              ]
            }
```

---

## 🔐 Configuração Segura (GitHub Secrets)

### 1. Criar Role IAM no AWS

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesisanalytics:*",
        "kinesis:*",
        "iam:PassRole",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. GitHub Secrets a Configurar

```
AWS_ROLE_ARN = arn:aws:iam::123456789:role/github-actions-flink-role
SLACK_WEBHOOK = https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

---

## 📊 Comparação: 3 Abordagens

| Aspecto | Script Bash Local | Terraform Manual | CI/CD Automático |
|---------|-------------------|------------------|------------------|
| **Segurança** | ❌ Baixa | ⚠️ Média | ✅ Alta |
| **Auditoria** | ❌ Nenhuma | ⚠️ Parcial | ✅ Completa |
| **Reprodutibilidade** | ❌ Difícil | ✅ Fácil | ✅ Perfeita |
| **Ambiente Prod** | ❌ Não | ✅ Sim | ✅ Sim |
| **Facilidade** | ✅ Fácil | ✅ Fácil | ⚠️ Complexo (setup) |
| **Rollback** | ❌ Manual | ✅ terraform destroy | ✅ Automático |
| **Controle Dev** | ✅ Total | ✅ Total | ⚠️ Limitado |

---

## 🚀 Recomendação Final

### Para Desenvolvimento Local
```bash
# Use o script bash
bash app/flink-sql-application/deploy_flink_sql.sh start
```

### Para Staging/Produção
```bash
# Use Terraform via CI/CD
git push main
# → GitHub Actions automaticamente:
#   1. Valida
#   2. Aplica Terraform
#   3. Inicia Flink
#   4. Testa
#   5. Notifica
```

### Nunca Execute em Produção
```bash
# ❌ EVITE em produção
bash deploy_flink_sql.sh start    # Manual inseguro
aws cli commands manualmente       # Sem rastreamento
```

---

## 📝 Passos para Implementar

### 1. Atualizar Terraform (main.tf + variables.tf)
✅ Adicionar `aws_kinesisanalyticsv2_application_start`  
✅ Adicionar variáveis `auto_start_application` e `environment`

### 2. Criar GitHub Actions Workflow
✅ Arquivo `.github/workflows/deploy-flink.yml`

### 3. Configurar AWS IAM + GitHub Secrets
✅ Criar Role IAM com permissões KDA  
✅ Adicionar `AWS_ROLE_ARN` e `SLACK_WEBHOOK` em Secrets

### 4. Desabilitar Deploy Local em Produção
✅ Documentação: "Nunca execute bash script em produção"  
✅ Removê-lo de ambientes prod ou proteger acesso

---

## 🎯 Fluxo de Trabalho Recomendado

```
1. DESENVOLVIMENTO
   Dev edita código SQL/Terraform
   ↓
   Testa localmente: bash deploy_flink_sql.sh start
   ↓
   git commit + git push (branch feature)

2. REVIEW
   PR criado no GitHub
   GitHub Actions: validate + plan
   ↓
   DevOps/Tech Lead revisa plan

3. MERGE
   PR aprovado
   ↓
   git merge main
   ↓
   GitHub Actions: apply + test
   ↓
   Flink inicia automaticamente

4. MONITORING
   CloudWatch alerta se problema
   Slack notifica status
   ↓
   Se erro: rollback via terraform destroy + revert commit
```

---

## 🔧 Próximas Ações

1. ✅ Script Bash já existe para desenvolvimento local
2. ⏳ **CRIAR**: Atualizar terraform para auto-start (main.tf + variables.tf)
3. ⏳ **CRIAR**: GitHub Actions workflow (.github/workflows/deploy-flink.yml)
4. ⏳ **CRIAR**: Script Python para testar data flow
5. ⏳ **CRIAR**: Documentação de setup de IAM + Secrets

---

**Conclusão**: Use Terraform via CI/CD para produção, script bash apenas para desenvolvimento local.
