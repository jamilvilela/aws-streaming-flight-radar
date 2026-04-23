#!/bin/bash
# ============================================================================
# Manage KDA Alert Subscriptions
# ============================================================================
# This script manages SNS subscriptions for KDA Flink alerts
# 
# NOTE: SNS Topic is now created by Terraform module/sns
#       This script only manages subscriptions (email confirmation, etc)
# ============================================================================

set -e

# Configuration
PROJECT_NAME="flight-radar"
REGION="us-east-1"
SNS_TOPIC_NAME="${PROJECT_NAME}-kda-alerts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# ============================================================================
# 1. Get SNS Topic ARN from Terraform Outputs
# ============================================================================

echo -e "\n${BLUE}=== KDA Alert Subscriptions Management ===${NC}\n"
log_info "Fetching SNS topic ARN from Terraform outputs..."

# Try to get from terraform outputs
if command -v terraform &> /dev/null; then
  SNS_TOPIC_ARN=$(terraform -chdir=./infra output -raw sns_topic_arn 2>/dev/null || echo "")
fi

# If not from Terraform, query AWS
if [ -z "$SNS_TOPIC_ARN" ]; then
  log_warning "Terraform output not available, querying AWS..."
  
  SNS_TOPIC_ARN=$(aws sns list-topics \
    --region "$REGION" \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text)
fi

if [ -z "$SNS_TOPIC_ARN" ]; then
  log_error "SNS topic not found: $SNS_TOPIC_NAME"
  echo "Make sure to run: terraform apply"
  exit 1
fi

log_success "Found SNS topic: $SNS_TOPIC_ARN"

# ============================================================================
# 2. Setup Email Subscription (AWS Native)
# ============================================================================

setup_email() {
  echo -e "\n${YELLOW}--- Email Subscription ---${NC}"
  read -p "Enter email address for alerts (or skip): " email
  
  if [ -z "$email" ]; then
    log_warning "Skipped email subscription"
    return
  fi
  
  # Validate email format
  if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid email format: $email"
    return
  fi
  
  log_info "Subscribing $email to SNS topic..."
  
  SUBSCRIPTION_ARN=$(aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$email" \
    --region "$REGION" \
    --query 'SubscriptionArn' \
    --output text)
  
  log_success "Subscription created (ARN: $SUBSCRIPTION_ARN)"
  log_warning "📧 Check your email inbox and confirm the subscription"
  log_warning "   (AWS sends confirmation link)"
}

# ============================================================================
# 4. List Current Subscriptions
# ============================================================================

list_subscriptions() {
  echo -e "\n${BLUE}--- Current SNS Subscriptions ---${NC}\n"
  
  # Check if there are subscriptions
  SUBSCRIPTION_COUNT=$(aws sns list-subscriptions-by-topic \
    --topic-arn "$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --query 'length(Subscriptions)' \
    --output text)
  
  if [ "$SUBSCRIPTION_COUNT" -eq 0 ]; then
    log_warning "No subscriptions found for topic"
    return
  fi
  
  aws sns list-subscriptions-by-topic \
    --topic-arn "$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' \
    --output table
  
  log_success "Total subscriptions: $SUBSCRIPTION_COUNT"
}

# ============================================================================
# 5. Delete a Subscription
# ============================================================================

delete_subscription() {
  echo -e "\n${YELLOW}--- Delete Subscription ---${NC}"
  
  read -p "Enter subscription ARN to delete (or skip): " sub_arn
  
  if [ -z "$sub_arn" ]; then
    log_warning "Skipped"
    return
  fi
  
  log_info "Deleting subscription: $sub_arn"
  
  aws sns unsubscribe \
    --subscription-arn "$sub_arn" \
    --region "$REGION"
  
  log_success "Subscription deleted"
}

# ============================================================================
# 6. Test Alarm Notification
# ============================================================================

test_alarm() {
  echo -e "\n${YELLOW}--- Test Alarm Notification ---${NC}"
  read -p "Send test message to SNS? (y/n): " test_confirm
  
  if [ "$test_confirm" != "y" ]; then
    return
  fi
  
  log_info "Publishing test message to SNS..."
  
  aws sns publish \
    --topic-arn "$SNS_TOPIC_ARN" \
    --subject "Test: KDA Alert System Working" \
    --message "This is a test notification from KDA Alert system.
    
If you see this message, SNS and email delivery is working correctly!

Event Type: System Test
Alert Level: INFO
Timestamp: $(date)

---
AWS Streaming Flight Radar
SNS Topic: $SNS_TOPIC_ARN" \
    --region "$REGION"
  
  log_success "Test message sent!"
  log_info "Check your email for the test notification"
}

# ============================================================================
# 7. Show Alarm Status
# ============================================================================

show_alarms() {
  echo -e "\n${BLUE}--- CloudWatch Alarms Status ---${NC}\n"
  
  # Check if any alarms exist
  ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "$PROJECT_NAME-kda" \
    --region "$REGION" \
    --query 'length(MetricAlarms)' \
    --output text)
  
  if [ "$ALARM_COUNT" -eq 0 ]; then
    log_warning "No KDA alarms found"
    return
  fi
  
  aws cloudwatch describe-alarms \
    --alarm-name-prefix "$PROJECT_NAME-kda" \
    --region "$REGION" \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateUpdatedTimestamp]' \
    --output table
  
  log_success "Total alarms: $ALARM_COUNT"
}

# ============================================================================
# 8. Show SNS Topic Details
# ============================================================================

show_topic_details() {
  echo -e "\n${BLUE}--- SNS Topic Details ---${NC}\n"
  
  aws sns get-topic-attributes \
    --topic-arn "$SNS_TOPIC_ARN" \
    --region "$REGION" \
    --query 'Attributes' \
    --output table
}

# ============================================================================
# Main Menu
# ============================================================================

main() {
  while true; do
    echo -e "\n${BLUE}SNS Topic: ${GREEN}$SNS_TOPIC_ARN${NC}"
    echo -e "\n${BLUE}Choose action:${NC}"
    echo "1) Add Email subscription"
    echo "2) List Subscriptions"
    echo "3) Delete Subscription"
    echo "4) Test Alarm Notification"
    echo "5) Show Alarm Status"
    echo "6) Show Topic Details"
    echo "7) Exit"
    read -p "Enter choice (1-7): " choice
    
    case $choice in
      1) setup_email ;;
      2) list_subscriptions ;;
      3) delete_subscription ;;
      4) test_alarm ;;
      5) show_alarms ;;
      6) show_topic_details ;;
      7) log_success "Goodbye!"; exit 0 ;;
      *) log_error "Invalid choice" ;;
    esac
  done
}

# ============================================================================
# Validate Prerequisites
# ============================================================================

validate_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install: https://aws.amazon.com/cli/"
    exit 1
  fi
  
  # Check AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials not configured"
    exit 1
  fi
  
  log_success "Prerequisites OK"
}

# ============================================================================
# Run
# ============================================================================

validate_prerequisites
main
