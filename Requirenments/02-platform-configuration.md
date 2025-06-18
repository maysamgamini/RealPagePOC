# n8n Workflow Configuration Guide - Voice AI Property Management POC

## Overview
This document provides detailed configuration guidance for n8n workflows in the Voice AI Property Management POC, covering Retell AI integration, Twilio voice/SMS handling, Google Sheets data management, and automated 60-day notice workflows.

## Architecture Overview

### Workflow Components
```
┌─────────────────────────────────────────────────────────────┐
│                   n8n Workflow Architecture                 │
├─────────────────────────────────────────────────────────────┤
│  Twilio Webhook → n8n → Retell AI → Voice Response          │
│        ↓              ↓         ↓           ↓               │
│   Call Data      Processing   NLP      Audio Output         │
│        ↓              ↓         ↓           ↓               │
│  Google Sheets ← Data Sync ← Analysis ← Conversation        │
│        ↓              ↓         ↓           ↓               │
│   Tenant DB     Logging    Updates    Follow-up Actions     │
└─────────────────────────────────────────────────────────────┘
```

## Core Workflow Configurations

### 1. Tenant Inquiry Handler Workflow

#### Workflow Overview
Handles inbound tenant calls for common inquiries like rent payments, maintenance requests, and lease information.

```json
{
  "name": "Tenant Inquiry Handler",
  "active": true,
  "nodes": [
    {
      "parameters": {
        "path": "tenant-call",
        "httpMethod": "POST",
        "responseMode": "responseNode"
      },
      "name": "Twilio Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [240, 300]
    },
    {
      "parameters": {
        "functionCode": "// Extract caller information\nconst callSid = items[0].json.CallSid;\nconst from = items[0].json.From;\nconst to = items[0].json.To;\n\n// Format phone number\nconst phoneNumber = from.replace('+1', '');\n\nreturn [{\n  json: {\n    callSid: callSid,\n    phoneNumber: phoneNumber,\n    originalFrom: from,\n    to: to,\n    timestamp: new Date().toISOString()\n  }\n}];"
      },
      "name": "Extract Call Data",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [460, 300]
    },
    {
      "parameters": {
        "operation": "read",
        "documentId": "{{$env.GOOGLE_SHEETS_TENANT_DB_ID}}",
        "sheetName": "Tenants",
        "range": "A:Z",
        "keyRow": 1,
        "dataStartRow": 2
      },
      "name": "Lookup Tenant",
      "type": "n8n-nodes-base.googleSheets",
      "typeVersion": 3,
      "position": [680, 300]
    },
    {
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{$json.phoneNumber}}",
              "operation": "isNotEmpty"
            }
          ]
        }
      },
      "name": "Tenant Found?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [900, 300]
    },
    {
      "parameters": {
        "url": "https://api.retell.ai/v1/call/start",
        "authentication": "headerAuth",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "Bearer {{$env.RETELL_AI_API_KEY}}"
            }
          ]
        },
        "sendBody": true,
        "bodyParameters": {
          "parameters": [
            {
              "name": "phone_number",
              "value": "={{$node['Extract Call Data'].json['phoneNumber']}}"
            },
            {
              "name": "context",
              "value": "={{JSON.stringify($node['Lookup Tenant'].json)}}"
            },
            {
              "name": "prompt",
              "value": "You are a helpful property management assistant. The tenant {{$node['Lookup Tenant'].json['tenant_name']}} is calling. Help them with their inquiry about rent, maintenance, or lease information."
            }
          ]
        }
      },
      "name": "Start Retell AI Call",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [1120, 200]
    },
    {
      "parameters": {
        "respondWith": "text",
        "responseBody": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response>\n    <Say>Please hold while we connect you to our AI assistant.</Say>\n    <Redirect>{{$node['Start Retell AI Call'].json['webhook_url']}}</Redirect>\n</Response>"
      },
      "name": "TwiML Response - Known Tenant",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1,
      "position": [1340, 200]
    },
    {
      "parameters": {
        "respondWith": "text",
        "responseBody": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response>\n    <Say>Thank you for calling. Please hold while we gather your information.</Say>\n    <Gather input=\"dtmf\" numDigits=\"10\" action=\"/webhook/collect-phone\">\n        <Say>Please enter your 10-digit phone number.</Say>\n    </Gather>\n</Response>"
      },
      "name": "TwiML Response - Unknown Caller",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1,
      "position": [1120, 400]
    }
  ],
  "connections": {
    "Twilio Webhook": {
      "main": [
        [
          {
            "node": "Extract Call Data",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Extract Call Data": {
      "main": [
        [
          {
            "node": "Lookup Tenant",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Lookup Tenant": {
      "main": [
        [
          {
            "node": "Tenant Found?",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Tenant Found?": {
      "main": [
        [
          {
            "node": "Start Retell AI Call",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "TwiML Response - Unknown Caller",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Start Retell AI Call": {
      "main": [
        [
          {
            "node": "TwiML Response - Known Tenant",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
```

### 2. 60-Day Notice Automation Workflow

#### Workflow Overview
Automatically identifies lease expirations and sends 60-day notices via multiple channels.

```json
{
  "name": "60-Day Notice Automation",
  "active": true,
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hour",
              "expression": "9"
            }
          ]
        }
      },
      "name": "Daily Check Trigger",
      "type": "n8n-nodes-base.cron",
      "typeVersion": 1,
      "position": [240, 300]
    },
    {
      "parameters": {
        "operation": "read",
        "documentId": "{{$env.GOOGLE_SHEETS_TENANT_DB_ID}}",
        "sheetName": "Leases",
        "range": "A:Z",
        "keyRow": 1,
        "dataStartRow": 2
      },
      "name": "Get All Leases",
      "type": "n8n-nodes-base.googleSheets",
      "typeVersion": 3,
      "position": [460, 300]
    },
    {
      "parameters": {
        "functionCode": "const today = new Date();\nconst targetDate = new Date();\ntargetDate.setDate(today.getDate() + 60);\n\nconst leaseExpirations = [];\n\nfor (const lease of items) {\n  const leaseEndDate = new Date(lease.json.lease_end_date);\n  \n  // Check if lease expires in exactly 60 days\n  if (leaseEndDate.toDateString() === targetDate.toDateString()) {\n    leaseExpirations.push({\n      json: {\n        tenant_id: lease.json.tenant_id,\n        tenant_name: lease.json.tenant_name,\n        phone_number: lease.json.phone_number,\n        email: lease.json.email,\n        property_address: lease.json.property_address,\n        lease_end_date: lease.json.lease_end_date,\n        unit_number: lease.json.unit_number,\n        notice_date: today.toISOString().split('T')[0]\n      }\n    });\n  }\n}\n\nreturn leaseExpirations;"
      },
      "name": "Filter 60-Day Expirations",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [680, 300]
    },
    {
      "parameters": {
        "batchSize": 1,
        "options": {}
      },
      "name": "Process Each Tenant",
      "type": "n8n-nodes-base.splitInBatches",
      "typeVersion": 1,
      "position": [900, 300]
    },
    {
      "parameters": {
        "functionCode": "const tenant = items[0].json;\n\nconst noticeText = `Dear ${tenant.tenant_name},\n\nThis is to inform you that your lease for ${tenant.property_address}, Unit ${tenant.unit_number} will expire on ${tenant.lease_end_date}.\n\nPer your lease agreement, this serves as your 60-day notice. Please contact our office to discuss renewal options or move-out procedures.\n\nThank you,\nProperty Management Team`;\n\nreturn [{\n  json: {\n    ...tenant,\n    notice_text: noticeText,\n    notice_subject: `60-Day Lease Expiration Notice - ${tenant.property_address}`\n  }\n}];"
      },
      "name": "Generate Notice Text",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [1120, 300]
    },
    {
      "parameters": {
        "url": "https://api.retell.ai/v1/call/outbound",
        "authentication": "headerAuth",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "Bearer {{$env.RETELL_AI_API_KEY}}"
            }
          ]
        },
        "sendBody": true,
        "bodyParameters": {
          "parameters": [
            {
              "name": "to_number",
              "value": "={{$json.phone_number}}"
            },
            {
              "name": "from_number",
              "value": "{{$env.TWILIO_PHONE_NUMBER}}"
            },
            {
              "name": "prompt",
              "value": "You are calling to deliver a 60-day lease expiration notice. Be professional and helpful. The message is: {{$json.notice_text}}"
            }
          ]
        }
      },
      "name": "Make Voice Call",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 3,
      "position": [1340, 200]
    },
    {
      "parameters": {
        "authentication": "oAuth2Api",
        "to": "={{$json.email}}",
        "subject": "={{$json.notice_subject}}",
        "message": "={{$json.notice_text}}"
      },
      "name": "Send Email Notice",
      "type": "n8n-nodes-base.gmail",
      "typeVersion": 1,
      "position": [1340, 300]
    },
    {
      "parameters": {
        "authentication": "oAuth2Api",
        "to": "={{$json.phone_number}}",
        "message": "NOTICE: Your lease expires {{$json.lease_end_date}}. This is your 60-day notice. Please contact us to discuss renewal. -Property Management"
      },
      "name": "Send SMS Notice",
      "type": "n8n-nodes-base.twilio",
      "typeVersion": 1,
      "position": [1340, 400]
    },
    {
      "parameters": {
        "operation": "append",
        "documentId": "{{$env.GOOGLE_SHEETS_TENANT_DB_ID}}",
        "sheetName": "Notice_Log",
        "columns": {
          "mappingMode": "defineBelow",
          "value": {
            "tenant_id": "={{$json.tenant_id}}",
            "notice_date": "={{$json.notice_date}}",
            "notice_type": "60-Day Lease Expiration",
            "delivery_method": "Voice, Email, SMS",
            "status": "Sent",
            "lease_end_date": "={{$json.lease_end_date}}"
          }
        },
        "options": {}
      },
      "name": "Log Notice Delivery",
      "type": "n8n-nodes-base.googleSheets",
      "typeVersion": 3,
      "position": [1560, 300]
    }
  ],
  "connections": {
    "Daily Check Trigger": {
      "main": [
        [
          {
            "node": "Get All Leases",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Get All Leases": {
      "main": [
        [
          {
            "node": "Filter 60-Day Expirations",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Filter 60-Day Expirations": {
      "main": [
        [
          {
            "node": "Process Each Tenant",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Process Each Tenant": {
      "main": [
        [
          {
            "node": "Generate Notice Text",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Generate Notice Text": {
      "main": [
        [
          {
            "node": "Make Voice Call",
            "type": "main",
            "index": 0
          },
          {
            "node": "Send Email Notice",
            "type": "main",
            "index": 0
          },
          {
            "node": "Send SMS Notice",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Make Voice Call": {
      "main": [
        [
          {
            "node": "Log Notice Delivery",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Send Email Notice": {
      "main": [
        [
          {
            "node": "Log Notice Delivery",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Send SMS Notice": {
      "main": [
        [
          {
            "node": "Log Notice Delivery",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
```

### 3. Maintenance Request Handler Workflow

#### Workflow Overview
Processes maintenance requests submitted via voice calls and creates tickets in Google Sheets.

```json
{
  "name": "Maintenance Request Handler",
  "active": true,
  "nodes": [
    {
      "parameters": {
        "path": "maintenance-request",
        "httpMethod": "POST"
      },
      "name": "Retell AI Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [240, 300]
    },
    {
      "parameters": {
        "functionCode": "// Parse Retell AI response\nconst callData = items[0].json;\n\n// Extract maintenance request details\nconst requestDetails = {\n  tenant_phone: callData.caller_number,\n  request_type: callData.intent || 'General Maintenance',\n  description: callData.transcript || callData.summary,\n  urgency: callData.urgency || 'Medium',\n  timestamp: new Date().toISOString(),\n  call_id: callData.call_id,\n  status: 'New'\n};\n\nreturn [{ json: requestDetails }];"
      },
      "name": "Parse Request Details",
      "type": "n8n-nodes-base.function",
      "typeVersion": 1,
      "position": [460, 300]
    },
    {
      "parameters": {
        "operation": "read",
        "documentId": "{{$env.GOOGLE_SHEETS_TENANT_DB_ID}}",
        "sheetName": "Tenants",
        "range": "A:Z",
        "keyRow": 1,
        "dataStartRow": 2,
        "keyColumn": "phone_number"
      },
      "name": "Lookup Tenant Info",
      "type": "n8n-nodes-base.googleSheets",
      "typeVersion": 3,
      "position": [680, 300]
    },
    {
      "parameters": {
        "operation": "append",
        "documentId": "{{$env.GOOGLE_SHEETS_MAINTENANCE_ID}}",
        "sheetName": "Requests",
        "columns": {
          "mappingMode": "defineBelow",
          "value": {
            "request_id": "=CONCATENATE(\"REQ-\", TEXT(NOW(), \"YYYYMMDD-HHMMSS\"))",
            "tenant_name": "={{$node['Lookup Tenant Info'].json['tenant_name']}}",
            "tenant_phone": "={{$json.tenant_phone}}",
            "property_address": "={{$node['Lookup Tenant Info'].json['property_address']}}",
            "unit_number": "={{$node['Lookup Tenant Info'].json['unit_number']}}",
            "request_type": "={{$json.request_type}}",
            "description": "={{$json.description}}",
            "urgency": "={{$json.urgency}}",
            "status": "={{$json.status}}",
            "date_submitted": "={{$json.timestamp}}",
            "call_id": "={{$json.call_id}}"
          }
        }
      },
      "name": "Create Maintenance Ticket",
      "type": "n8n-nodes-base.googleSheets",
      "typeVersion": 3,
      "position": [900, 300]
    },
    {
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{$node['Parse Request Details'].json['urgency']}}",
              "value2": "High"
            }
          ]
        }
      },
      "name": "High Priority?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [1120, 300]
    },
    {
      "parameters": {
        "authentication": "oAuth2Api",
        "to": "{{$env.MAINTENANCE_MANAGER_EMAIL}}",
        "subject": "URGENT: High Priority Maintenance Request",
        "message": "A high priority maintenance request has been submitted:\n\nTenant: {{$node['Lookup Tenant Info'].json['tenant_name']}}\nProperty: {{$node['Lookup Tenant Info'].json['property_address']}}\nUnit: {{$node['Lookup Tenant Info'].json['unit_number']}}\nRequest: {{$node['Parse Request Details'].json['description']}}\nUrgency: {{$node['Parse Request Details'].json['urgency']}}\n\nPlease respond immediately."
      },
      "name": "Alert Maintenance Manager",
      "type": "n8n-nodes-base.gmail",
      "typeVersion": 1,
      "position": [1340, 200]
    },
    {
      "parameters": {
        "authentication": "oAuth2Api",
        "to": "={{$node['Parse Request Details'].json['tenant_phone']}}",
        "message": "Thank you for your maintenance request. We have received your request and will respond within 24 hours. Request ID: {{$node['Create Maintenance Ticket'].json['request_id']}}"
      },
      "name": "Send Confirmation SMS",
      "type": "n8n-nodes-base.twilio",
      "typeVersion": 1,
      "position": [1340, 400]
    }
  ],
  "connections": {
    "Retell AI Webhook": {
      "main": [
        [
          {
            "node": "Parse Request Details",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Parse Request Details": {
      "main": [
        [
          {
            "node": "Lookup Tenant Info",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Lookup Tenant Info": {
      "main": [
        [
          {
            "node": "Create Maintenance Ticket",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Create Maintenance Ticket": {
      "main": [
        [
          {
            "node": "High Priority?",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "High Priority?": {
      "main": [
        [
          {
            "node": "Alert Maintenance Manager",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "Send Confirmation SMS",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Alert Maintenance Manager": {
      "main": [
        [
          {
            "node": "Send Confirmation SMS",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
```

## Google Sheets Configuration

### Tenant Database Sheet Structure

```
| Column A | Column B | Column C | Column D | Column E | Column F | Column G |
|----------|----------|----------|----------|----------|----------|----------|
| tenant_id| tenant_name| phone_number| email | property_address| unit_number| lease_end_date|
| T001 | John Smith | 5551234567 | john@email.com | 123 Main St | 101 | 2024-12-31 |
| T002 | Jane Doe | 5559876543 | jane@email.com | 456 Oak Ave | 205 | 2024-11-15 |
```

### Maintenance Requests Sheet Structure

```
| Column A | Column B | Column C | Column D | Column E | Column F | Column G | Column H |
|----------|----------|----------|----------|----------|----------|----------|----------|
| request_id| tenant_name| tenant_phone| property_address| request_type| description| urgency| status|
| REQ-20241201-143022| John Smith| 5551234567| 123 Main St| Plumbing| Leaky faucet| Medium| New|
```

### Notice Log Sheet Structure

```
| Column A | Column B | Column C | Column D | Column E | Column F |
|----------|----------|----------|----------|----------|----------|
| tenant_id| notice_date| notice_type| delivery_method| status| lease_end_date|
| T001 | 2024-11-01 | 60-Day Lease Expiration | Voice, Email, SMS | Sent | 2024-12-31 |
```

## Retell AI Configuration

### Voice Model Settings
```javascript
const retellConfig = {
  voice_model: "eleven_labs_turbo",
  language: "en-US",
  voice_settings: {
    stability: 0.7,
    similarity_boost: 0.8,
    style: 0.2
  },
  conversation_config: {
    max_duration: 300, // 5 minutes
    silence_timeout: 10, // 10 seconds
    interruption_sensitivity: 0.7
  }
};
```

### Conversation Prompts
```javascript
const prompts = {
  greeting: "Hello! Thank you for calling [Property Name]. I'm your AI assistant. How can I help you today?",
  
  tenant_identification: "To better assist you, could you please provide your name or phone number?",
  
  rent_inquiry: "I can help you with rent-related questions. Would you like to check your balance, payment history, or make a payment?",
  
  maintenance_request: "I understand you need to report a maintenance issue. Could you please describe the problem and let me know if it's urgent?",
  
  lease_information: "I can provide information about your lease. What specific details would you like to know about?",
  
  escalation: "I understand this requires additional assistance. Let me connect you with a property manager. Please hold while I transfer your call."
};
```

## Twilio Configuration

### Phone Number Setup
```javascript
// Webhook configuration for Twilio phone number
const webhookConfig = {
  voice_url: "https://your-domain.com/webhook/tenant-call",
  voice_method: "POST",
  sms_url: "https://your-domain.com/webhook/sms-received",
  sms_method: "POST",
  status_callback: "https://your-domain.com/webhook/call-status"
};
```

### TwiML Response Templates
```xml
<!-- Standard greeting -->
<Response>
    <Say voice="alice">Thank you for calling. Please hold while we connect you to our AI assistant.</Say>
    <Redirect>https://retell-ai-endpoint.com/call/{{call_id}}</Redirect>
</Response>

<!-- Call forwarding to human agent -->
<Response>
    <Say voice="alice">Connecting you to a property manager. Please hold.</Say>
    <Dial>+1-555-MANAGER</Dial>
</Response>

<!-- Voicemail fallback -->
<Response>
    <Say voice="alice">We're currently unavailable. Please leave a message after the tone.</Say>
    <Record maxLength="120" action="/webhook/voicemail-received"/>
</Response>
```

## Environment Variables Configuration

### Required Environment Variables
```env
# n8n Configuration
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=your-secure-password
N8N_HOST=your-domain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://your-domain.com/

# Retell AI
RETELL_AI_API_KEY=your-retell-ai-api-key
RETELL_AI_AGENT_ID=your-agent-id

# Twilio
TWILIO_ACCOUNT_SID=your-twilio-account-sid
TWILIO_AUTH_TOKEN=your-twilio-auth-token
TWILIO_PHONE_NUMBER=+1-555-YOUR-NUMBER

# Google Sheets
GOOGLE_SHEETS_TENANT_DB_ID=your-tenant-database-sheet-id
GOOGLE_SHEETS_MAINTENANCE_ID=your-maintenance-requests-sheet-id
GOOGLE_SERVICE_ACCOUNT_EMAIL=your-service-account@project.iam.gserviceaccount.com

# Email Configuration
MAINTENANCE_MANAGER_EMAIL=manager@property-company.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

## Testing and Validation

### Workflow Testing Checklist
- [ ] Test inbound call handling with known tenant
- [ ] Test inbound call handling with unknown caller
- [ ] Verify Retell AI integration and voice quality
- [ ] Test maintenance request submission and ticket creation
- [ ] Validate Google Sheets data synchronization
- [ ] Test 60-day notice automation (use test date)
- [ ] Verify SMS and email delivery
- [ ] Test escalation to human agents
- [ ] Validate error handling and fallback scenarios

### Test Data Setup
```javascript
// Test tenant data for Google Sheets
const testTenants = [
  {
    tenant_id: "TEST001",
    tenant_name: "Test User",
    phone_number: "5551234567",
    email: "test@example.com",
    property_address: "123 Test Street",
    unit_number: "101",
    lease_end_date: "2024-12-31"
  }
];
```

## Monitoring and Maintenance

### Key Metrics to Monitor
- Call success rate and connection quality
- Retell AI response accuracy and conversation flow
- Google Sheets synchronization success
- SMS/email delivery rates
- Workflow execution times and errors
- Tenant satisfaction feedback

### Regular Maintenance Tasks
- Review and update conversation prompts
- Monitor API usage and costs
- Update tenant database regularly
- Test backup and recovery procedures
- Review and optimize workflow performance
- Update security credentials quarterly

This configuration guide provides the foundation for implementing effective voice AI workflows for property management using n8n, Retell AI, Twilio, and Google Sheets integration. 