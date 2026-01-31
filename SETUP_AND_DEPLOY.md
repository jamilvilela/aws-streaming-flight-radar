# 🚀 Setup e Deploy - Flight Radar Stream

Guia passo a passo para configurar credenciais e fazer deploy da infraestrutura Terraform.

---

## 📋 Índice

1. [Quick Start](#quick-start)
2. [Setup Detalhado](#setup-detalhado)
3. [Comandos Disponíveis](#comandos-disponíveis)
4. [Troubleshooting](#troubleshooting)
5. [Verificação Pós-Deploy](#verificação-pós-deploy)

---

## 🚀 Quick Start

### Linux/macOS:
```bash
# 1. Configure credenciais
cp .env.example .env
nano .env  # Edite com suas credenciais

# 2. Deploy completo (init + validate + plan + apply)
chmod +x setup-env.sh
./setup-env.sh --apply

# 3. Verifique logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow
```

### Windows PowerShell:
```powershell
# 1. Configure credenciais
Copy-Item .env.example -Destination .env
notepad .env  # Edite com suas credenciais

# 2. Deploy completo
.\setup-env.ps1 -Action apply -AutoApprove

# 3. Verifique logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow
```

---

## 🔧 Setup Detalhado

### Passo 1: Criar arquivo .env

#### Linux/macOS:
```bash
cp .env.example .env
nano .env
```

#### Windows:
```powershell
Copy-Item .env.example -Destination .env
notepad .env
```

### Passo 2: Configurar credenciais

Edite o arquivo `.env` com suas credenciais:

```env
# OpenSky API
OPENSKY_USERNAME=seu_usuario_opensky
OPENSKY_PASSWORD=sua_senha_opensky

# AWS
AWS_REGION=us-east-1

# Terraform
TF_VAR_environment=development
```

⚠️ **IMPORTANTE**: Nunca faça commit de `.env`! Está já no `.gitignore`.

### Passo 3: Verificar AWS Credentials

Certifique-se de que suas credenciais AWS estão configuradas:

#### Linux/macOS:
```bash
# Opção 1: Variáveis de ambiente
export AWS_ACCESS_KEY_ID="xxx"
export AWS_SECRET_ACCESS_KEY="xxx"

# Opção 2: AWS CLI config
aws configure

# Verificar
aws sts get-caller-identity
```

#### Windows PowerShell:
```powershell
# Opção 1: Variáveis de ambiente
$env:AWS_ACCESS_KEY_ID = "xxx"
$env:AWS_SECRET_ACCESS_KEY = "xxx"

# Opção 2: AWS CLI config
aws configure

# Verificar
aws sts get-caller-identity
```

### Passo 4: Execute o setup

#### Linux/macOS - Apenas carregar variáveis:
```bash
chmod +x setup-env.sh  # Primeira vez
source ./setup-env.sh
```

#### Windows - Apenas carregar variáveis:
```powershell
.\setup-env.ps1
```

---

## 📝 Comandos Disponíveis

### Linux/macOS - setup-env.sh

#### 1. Apenas carregar variáveis (padrão):
```bash
source ./setup-env.sh
cd infra && terraform plan
```

#### 2. Apenas terraform init:
```bash
./setup-env.sh --init
```

#### 3. Apenas terraform validate:
```bash
./setup-env.sh --validate
```

#### 4. Apenas terraform plan:
```bash
./setup-env.sh --plan
```

#### 5. Apenas terraform apply (com auto-approve):
```bash
./setup-env.sh --apply
```

#### 6. Deploy completo (init + validate + plan + apply):
```bash
./setup-env.sh --apply
```

### Windows - setup-env.ps1

#### 1. Apenas carregar variáveis (padrão):
```powershell
.\setup-env.ps1
cd infra
terraform plan -var-file=tfvars/terraform.tfvars
```

#### 2. Apenas terraform init:
```powershell
.\setup-env.ps1 -Action init
```

#### 3. Apenas terraform validate:
```powershell
.\setup-env.ps1 -Action validate
```

#### 4. Apenas terraform plan:
```powershell
.\setup-env.ps1 -Action plan
```

#### 5. Apenas terraform apply (com auto-approve):
```powershell
.\setup-env.ps1 -Action apply -AutoApprove
```

#### 6. Deploy completo:
```powershell
.\setup-env.ps1 -Action full -AutoApprove
```

---

## 🔍 O que o Setup Faz

```
setup-env.sh / setup-env.ps1
│
├─ Step 1: Carrega .env
│  └─ Lê arquivo .env
│  └─ Exporta variáveis de ambiente
│
├─ Step 2: Verifica credenciais OpenSky
│  └─ Confirma OPENSKY_USERNAME e OPENSKY_PASSWORD
│  └─ Converte para TF_VAR_* para Terraform
│
├─ Step 3: Verifica credenciais AWS
│  └─ Confirma AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY
│  └─ Avisa se não estão definidas (mas continua)
│
├─ Step 4: Navega para diretório infra/
│  └─ Muda para diretório onde Terraform está
│
└─ Step 5: Executa Terraform (se --apply ou -Action apply)
   ├─ terraform init
   ├─ terraform validate
   ├─ terraform plan
   └─ terraform apply
      └─ Verifica outputs pós-deploy
```

---

## 🧪 Verificação Pós-Deploy

### Depois que `terraform apply` completar:

#### 1. Verificar Secrets Manager:
```bash
aws secretsmanager get-secret-value \
  --secret-id flight-radar-stream-opensky-credentials \
  --region us-east-1
```

#### 2. Verificar Lambda foi criado:
```bash
aws lambda list-functions \
  --region us-east-1 \
  | grep flight-radar-stream-ingest-flights
```

#### 3. Verificar Kinesis Stream:
```bash
aws kinesis describe-stream \
  --stream-name flight-radar-kinesis-stream-flights \
  --region us-east-1
```

#### 4. Verificar IAM Role:
```bash
aws iam get-role \
  --role-name flight-radar-stream-lambda-flights-role
```

#### 5. Testar Lambda invocação:
```bash
aws lambda invoke \
  --function-name flight-radar-stream-ingest-flights \
  --region us-east-1 \
  /tmp/response.json

cat /tmp/response.json  # Linux/macOS
type C:\tmp\response.json  # Windows
```

#### 6. Ver logs Lambda em tempo real:
```bash
# Terminal 1: Acompanhar logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights \
  --follow \
  --region us-east-1

# Terminal 2: Invocar Lambda
aws lambda invoke \
  --function-name flight-radar-stream-ingest-flights \
  --region us-east-1 \
  /tmp/response.json
```

#### 7. Verificar se dados chegam no Kinesis:
```bash
# Obter shard ID
SHARD_ID=$(aws kinesis list-shards \
  --stream-name flight-radar-kinesis-stream-flights \
  --region us-east-1 \
  --query 'Shards[0].ShardId' \
  --output text)

# Obter shard iterator
SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name flight-radar-kinesis-stream-flights \
  --shard-id $SHARD_ID \
  --shard-iterator-type LATEST \
  --region us-east-1 \
  --query 'ShardIterator' \
  --output text)

# Listar registros
aws kinesis get-records \
  --shard-iterator $SHARD_ITERATOR \
  --region us-east-1
```

---

## ⚠️ Troubleshooting

### Problema: "Arquivo .env não encontrado"

```
❌ Erro: Arquivo .env não encontrado!
```

**Solução:**
```bash
cp .env.example .env
```

### Problema: "Credenciais OpenSky não estão definidas"

```
⚠️  Credenciais OpenSky não estão definidas em .env
```

**Solução:**
```bash
# Edite .env
nano .env

# Adicione:
OPENSKY_USERNAME=seu_usuario
OPENSKY_PASSWORD=sua_senha

# Salve (Ctrl+X, Y, Enter no nano)
```

### Problema: "AWS credentials não encontradas"

```
⚠️  AWS credentials não encontradas
```

**Solução 1 - Usar AWS CLI:**
```bash
aws configure
# Digite: Access Key ID, Secret Access Key, Region, Output Format
```

**Solução 2 - Exportar variáveis (Linux/macOS):**
```bash
export AWS_ACCESS_KEY_ID="seu_access_key"
export AWS_SECRET_ACCESS_KEY="sua_secret_key"
export AWS_REGION="us-east-1"
```

**Solução 3 - Exportar variáveis (Windows):**
```powershell
$env:AWS_ACCESS_KEY_ID = "seu_access_key"
$env:AWS_SECRET_ACCESS_KEY = "sua_secret_key"
$env:AWS_REGION = "us-east-1"
```

### Problema: "terraform init falhou"

**Possíveis causas:**
- Backend S3 não existe
- IAM permissions insuficientes
- Arquivo .terraform.lock.hcl corrompido

**Soluções:**
```bash
# 1. Verificar permissions
aws sts get-caller-identity

# 2. Limpar cache Terraform
cd infra
rm -rf .terraform
rm .terraform.lock.hcl

# 3. Tentar novamente
./setup-env.sh --init
```

### Problema: "terraform validate falhou"

**Solução:**
```bash
cd infra
terraform validate -json  # Ver erro detalhado
```

### Problema: "terraform plan falhou"

**Possíveis causas:**
- Variáveis não definidas
- Sintaxe incorreta em .tf files
- Módulos não encontrados

**Soluções:**
```bash
cd infra
terraform plan -var-file=tfvars/terraform.tfvars -json | grep -i error
```

### Problema: "terraform apply falhou"

**Possíveis causas:**
- Recursos já existem na AWS
- Permissões IAM insuficientes
- Cota AWS atingida

**Soluções:**
```bash
# Ver erro detalhado
cd infra
terraform apply -var-file=tfvars/terraform.tfvars -json

# Se recurso já existe, importar:
terraform import aws_secretsmanager_secret.opensky \
  flight-radar-stream-opensky-credentials
```

### Problema: Lambda falha ao invocar

**Verificar:**
```bash
# Ver logs
aws logs tail /aws/lambda/flight-radar-stream-ingest-flights --follow

# Invocar manualmente
aws lambda invoke \
  --function-name flight-radar-stream-ingest-flights \
  /tmp/response.json

# Ver resposta
cat /tmp/response.json
```

---

## 📊 Fluxo Completo

```
┌─────────────────────────────────────────────────────────────┐
│  1. Configuração Inicial                                    │
├─────────────────────────────────────────────────────────────┤
│  $ cp .env.example .env                                     │
│  $ nano .env  (editar com credenciais)                      │
│  $ aws configure  (configurar AWS)                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. Executar Setup & Deploy                                 │
├─────────────────────────────────────────────────────────────┤
│  $ ./setup-env.sh --apply                                   │
│  OR                                                          │
│  $ .\setup-env.ps1 -Action apply -AutoApprove               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. Interno: setup-env.sh/ps1                               │
├─────────────────────────────────────────────────────────────┤
│  ├─ Carrega .env                                             │
│  ├─ Verifica credenciais                                     │
│  ├─ Exporta TF_VAR_*                                         │
│  ├─ terraform init                                           │
│  ├─ terraform validate                                       │
│  ├─ terraform plan                                           │
│  └─ terraform apply                                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. Recursos Criados na AWS                                 │
├─────────────────────────────────────────────────────────────┤
│  ✅ AWS Secrets Manager (credenciais OpenSky)               │
│  ✅ Lambda Function (ingest-flights)                         │
│  ✅ Kinesis Stream (flight-radar-stream-flights)            │
│  ✅ EventBridge Rule (agendador Lambda)                     │
│  ✅ CloudWatch Logs (logs Lambda)                           │
│  ✅ IAM Roles & Policies                                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. Verificação Pós-Deploy                                  │
├─────────────────────────────────────────────────────────────┤
│  $ aws secretsmanager get-secret-value ...                  │
│  $ aws lambda list-functions ...                            │
│  $ aws logs tail /aws/lambda/... --follow                   │
│  $ aws lambda invoke ... /tmp/response.json                 │
│  $ aws kinesis get-records ...                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Checklist Pré-Deploy

- [ ] `.env` criado com credenciais OpenSky reais
- [ ] `.env` NÃO está em staging (verificar `git status`)
- [ ] AWS credentials configuradas (`aws sts get-caller-identity` funciona)
- [ ] Terraform instalado (`terraform version`)
- [ ] Permissions na conta AWS para criar recursos
- [ ] Espaço em disco suficiente

---

## ✅ Checklist Pós-Deploy

- [ ] Setup executado sem erros
- [ ] Terraform apply completou com sucesso
- [ ] Secrets Manager tem o secret criado
- [ ] Lambda function existe e é invocável
- [ ] Kinesis stream criado
- [ ] EventBridge rule agendada
- [ ] Logs Lambda estão sendo gravados
- [ ] Lambda consegue acessar Secrets Manager (sem erro de permission)

---

## 🎯 Próximas Etapas

1. **Teste Manual**: Invoque Lambda e verifique logs
2. **Monitoramento**: Configure CloudWatch alarms
3. **Escalabilidade**: Ajuste shard count do Kinesis conforme necessário
4. **CI/CD**: Implemente GitHub Actions para deploy automático

---

**Last Updated**: 2026-01-20  
**Status**: Production Ready ✅
