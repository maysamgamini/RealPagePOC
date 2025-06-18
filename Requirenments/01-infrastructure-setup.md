# Infrastructure Setup Guide - Voice AI Property Management POC

## Overview
This document outlines the infrastructure setup for the Voice AI Property Management POC, including n8n deployment, Retell AI integration, Twilio configuration, and Google Sheets connectivity.

## Prerequisites
- **Cloud Account**: AWS or Azure account with appropriate permissions
- **Domain**: For SSL certificates and webhook endpoints
- **API Keys**: Retell AI, Twilio, and Google Sheets API credentials
- **Local Tools**: Docker, kubectl (optional for cloud deployment)

## Architecture Overview

### System Components
```
┌─────────────────────────────────────────────────────────────┐
│                Voice AI Property Management                 │
├─────────────────────────────────────────────────────────────┤
│  Tenant → Phone Call → Twilio → Retell AI → n8n            │
│                          ↓         ↓        ↓              │
│                     Call Routing   NLP   Workflows          │
│                          ↓         ↓        ↓              │
│                     Voice Response ↓   Google Sheets       │
│                          ↓         ↓        ↓              │
│                     SMS/Email → Logging → Data Updates     │
└─────────────────────────────────────────────────────────────┘
```

## Phase 1: n8n Infrastructure Setup

### Option A: Cloud Deployment (Recommended)

#### 1.1 AWS EC2 Setup
```bash
# Launch EC2 instance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1d0 \
  --instance-type t3.medium \
  --key-name your-key-pair \
  --security-group-ids sg-your-security-group \
  --subnet-id subnet-your-subnet

# Connect to instance
ssh -i your-key.pem ec2-user@your-instance-ip
```

#### 1.2 Docker Installation
```bash
# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### 1.3 n8n Deployment
```yaml
# docker-compose.yml
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=CHANGE_ME_ADMIN_PASSWORD
      - N8N_HOST=your-domain.com
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://your-domain.com/
      - GENERIC_TIMEZONE=America/New_York
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network

  postgres:
    image: postgres:13
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=n8n
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=CHANGE_ME_DB_PASSWORD
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-network

volumes:
  n8n_data:
  postgres_data:

networks:
  n8n-network:
    driver: bridge
```

#### 1.4 SSL Certificate Setup
```bash
# Install Certbot
sudo yum install -y certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot certonly --standalone -d your-domain.com

# Configure Nginx reverse proxy
sudo yum install -y nginx
```

```nginx
# /etc/nginx/conf.d/n8n.conf
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Option B: Local Development Setup

#### 1.1 Local Docker Setup
```bash
# Clone repository
git clone https://github.com/your-org/voice-ai-property-management.git
cd voice-ai-property-management

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env
```

```env
# .env file
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=your-secure-password
POSTGRES_PASSWORD=your-db-password
RETELL_AI_API_KEY=your-retell-ai-key
TWILIO_ACCOUNT_SID=your-twilio-sid
TWILIO_AUTH_TOKEN=your-twilio-token
GOOGLE_SHEETS_CREDENTIALS=your-google-credentials
```

#### 1.2 Start Services
```bash
# Start n8n and database
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f n8n
```

## Phase 2: External Service Setup

### 2.1 Retell AI Configuration

#### Create Retell AI Account
1. Sign up at [Retell AI](https://retell.ai)
2. Create a new project
3. Generate API key
4. Configure voice model and settings

#### API Integration
```javascript
// Retell AI webhook configuration in n8n
const retellConfig = {
  apiKey: "{{$env.RETELL_AI_API_KEY}}",
  endpoint: "https://api.retell.ai/v1/",
  voiceModel: "eleven_labs_turbo",
  language: "en-US"
};
```

### 2.2 Twilio Setup

#### Account Configuration
1. Create Twilio account
2. Purchase phone number
3. Configure webhook URLs
4. Set up SMS and Voice services

#### Webhook Configuration
```bash
# Configure Twilio webhooks
curl -X POST https://api.twilio.com/2010-04-01/Accounts/YOUR_ACCOUNT_SID/IncomingPhoneNumbers/YOUR_PHONE_NUMBER_SID.json \
  --data-urlencode "VoiceUrl=https://your-domain.com/webhook/twilio-voice" \
  --data-urlencode "SmsUrl=https://your-domain.com/webhook/twilio-sms" \
  -u YOUR_ACCOUNT_SID:YOUR_AUTH_TOKEN
```

### 2.3 Google Sheets API Setup

#### Enable Google Sheets API
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Enable Google Sheets API
3. Create service account
4. Download credentials JSON
5. Share spreadsheet with service account email

#### Service Account Configuration
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "your-key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n",
  "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
  "client_id": "your-client-id",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

## Phase 3: n8n Workflow Configuration

### 3.1 Basic Workflow Setup

#### Import Workflow Templates
```bash
# Download workflow templates
curl -O https://raw.githubusercontent.com/your-org/voice-ai-workflows/main/tenant-inquiry-workflow.json
curl -O https://raw.githubusercontent.com/your-org/voice-ai-workflows/main/60-day-notice-workflow.json
```

#### Configure Credentials in n8n
1. Open n8n interface (https://your-domain.com)
2. Go to Settings → Credentials
3. Add credentials for:
   - Retell AI API
   - Twilio
   - Google Sheets
   - HTTP Basic Auth

### 3.2 Workflow Templates

#### Tenant Inquiry Workflow
```json
{
  "name": "Tenant Inquiry Handler",
  "nodes": [
    {
      "name": "Twilio Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "twilio-voice",
        "httpMethod": "POST"
      }
    },
    {
      "name": "Retell AI Processing",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "https://api.retell.ai/v1/process",
        "method": "POST",
        "headers": {
          "Authorization": "Bearer {{$credentials.retellAI.apiKey}}"
        }
      }
    },
    {
      "name": "Google Sheets Update",
      "type": "n8n-nodes-base.googleSheets",
      "parameters": {
        "operation": "append",
        "sheetId": "your-sheet-id",
        "range": "A:Z"
      }
    }
  ]
}
```

#### 60-Day Notice Workflow
```json
{
  "name": "60-Day Notice Automation",
  "nodes": [
    {
      "name": "Schedule Trigger",
      "type": "n8n-nodes-base.cron",
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hour",
              "expression": "9"
            }
          ]
        }
      }
    },
    {
      "name": "Check Lease Expiration",
      "type": "n8n-nodes-base.googleSheets",
      "parameters": {
        "operation": "read",
        "sheetId": "your-sheet-id",
        "range": "A:Z"
      }
    },
    {
      "name": "Generate Notice",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": "// Generate 60-day notice logic"
      }
    },
    {
      "name": "Send via Twilio",
      "type": "n8n-nodes-base.twilio",
      "parameters": {
        "operation": "send",
        "to": "{{$json.phone}}",
        "message": "{{$json.notice_text}}"
      }
    }
  ]
}
```

## Phase 4: Security Configuration

### 4.1 Basic Security Setup
```bash
# Configure firewall
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Set up fail2ban
sudo yum install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 4.2 Environment Variables Security
```bash
# Create secure environment file
sudo nano /etc/environment

# Add secure variables
RETELL_AI_API_KEY=your-secure-key
TWILIO_AUTH_TOKEN=your-secure-token
GOOGLE_SHEETS_CREDENTIALS=your-secure-credentials
```

### 4.3 Database Security
```sql
-- Create dedicated database user
CREATE USER 'n8n_user'@'localhost' IDENTIFIED BY 'secure_password';
GRANT SELECT, INSERT, UPDATE, DELETE ON n8n.* TO 'n8n_user'@'localhost';
FLUSH PRIVILEGES;
```

## Phase 5: Monitoring Setup

### 5.1 Basic Monitoring
```yaml
# docker-compose.monitoring.yml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

### 5.2 Health Checks
```bash
# Create health check script
#!/bin/bash
# health-check.sh

# Check n8n status
curl -f http://localhost:5678/healthz || exit 1

# Check database connection
docker exec n8n-postgres pg_isready -U n8n || exit 1

# Check external APIs
curl -f https://api.retell.ai/health || exit 1
curl -f https://api.twilio.com/health || exit 1

echo "All services healthy"
```

## Phase 6: Testing and Validation

### 6.1 Component Testing
```bash
# Test n8n installation
curl http://localhost:5678

# Test webhook endpoints
curl -X POST http://localhost:5678/webhook/test \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'

# Test database connection
docker exec -it n8n-postgres psql -U n8n -c "SELECT 1;"
```

### 6.2 Integration Testing
```bash
# Test Twilio webhook
curl -X POST https://your-domain.com/webhook/twilio-voice \
  -d "From=%2B1234567890&To=%2B0987654321&CallSid=test123"

# Test Google Sheets integration
# (Run test workflow in n8n interface)
```

## Phase 7: Deployment Checklist

### 7.1 Pre-Deployment
- [ ] SSL certificates configured
- [ ] Domain DNS properly configured
- [ ] All API keys and credentials secured
- [ ] Firewall rules configured
- [ ] Backup procedures in place
- [ ] Monitoring alerts configured

### 7.2 Go-Live Checklist
- [ ] Test all workflows end-to-end
- [ ] Verify webhook endpoints accessible
- [ ] Confirm phone number routing
- [ ] Test emergency escalation procedures
- [ ] Validate data synchronization
- [ ] Document troubleshooting procedures

## Troubleshooting

### Common Issues

#### n8n Connection Issues
```bash
# Check n8n logs
docker logs n8n

# Restart n8n service
docker-compose restart n8n

# Check port accessibility
netstat -tlnp | grep 5678
```

#### Webhook Issues
```bash
# Test webhook accessibility
curl -I https://your-domain.com/webhook/test

# Check SSL certificate
openssl s_client -connect your-domain.com:443

# Verify DNS resolution
nslookup your-domain.com
```

#### Database Issues
```bash
# Check database status
docker exec n8n-postgres pg_isready

# View database logs
docker logs n8n-postgres

# Connect to database
docker exec -it n8n-postgres psql -U n8n
```

## Maintenance Procedures

### 6.1 Regular Maintenance
- **Weekly**: Review logs and performance metrics
- **Monthly**: Update SSL certificates if needed
- **Quarterly**: Update n8n and dependencies
- **Annually**: Review and rotate API keys

### 6.2 Backup Procedures
```bash
# Backup n8n data
docker exec n8n tar -czf /tmp/n8n-backup.tar.gz /home/node/.n8n
docker cp n8n:/tmp/n8n-backup.tar.gz ./backups/

# Backup database
docker exec n8n-postgres pg_dump -U n8n n8n > ./backups/database-backup.sql
```

This infrastructure setup provides a solid foundation for the Voice AI Property Management POC with proper security, monitoring, and maintenance procedures. 