# Retell AI Configuration Guide - Voice AI Property Management POC

## Overview
This document provides detailed configuration guidance for integrating Retell AI into the Voice AI Property Management system, covering account setup, agent configuration, conversation flows, and integration with n8n workflows.

## Retell AI Account Setup

### 1. Account Creation and Initial Setup

#### Create Retell AI Account
1. Visit [Retell AI Console](https://beta.retellai.com)
2. Sign up with business email
3. Complete account verification
4. Choose appropriate pricing plan

#### API Key Generation
```bash
# Generate API key in Retell AI console
# Store securely in environment variables
export RETELL_AI_API_KEY="your-api-key-here"
```

### 2. Agent Configuration

#### Create Property Management Agent
```json
{
  "agent_name": "PropertyManagementAssistant",
  "voice_id": "eleven_labs_turbo",
  "language": "en-US",
  "response_engine": "retell",
  "llm_websocket_url": "wss://your-domain.com/llm-websocket",
  "begin_message": "Hello! Thank you for calling [Property Name]. I'm your AI assistant. How can I help you today?",
  "general_prompt": "You are a helpful property management assistant. You can help tenants with rent payments, maintenance requests, lease information, and general inquiries. Always be professional, empathetic, and helpful. If you cannot resolve an issue, offer to connect the caller to a human agent.",
  "boosted_keywords": [
    "rent",
    "payment",
    "maintenance",
    "repair",
    "lease",
    "renewal",
    "emergency",
    "complaint",
    "move out",
    "deposit"
  ]
}
```

## Voice Configuration

### 1. Voice Settings

#### ElevenLabs Voice Configuration
```json
{
  "voice_model": "eleven_labs_turbo",
  "voice_settings": {
    "stability": 0.7,
    "similarity_boost": 0.8,
    "style": 0.2,
    "use_speaker_boost": true
  },
  "voice_characteristics": {
    "gender": "female",
    "age": "adult",
    "accent": "american",
    "tone": "professional_friendly"
  }
}
```

#### Alternative Voice Options
```json
{
  "voice_options": [
    {
      "name": "Professional Female",
      "voice_id": "eleven_labs_turbo",
      "description": "Clear, professional female voice"
    },
    {
      "name": "Friendly Male",
      "voice_id": "eleven_labs_adam",
      "description": "Warm, approachable male voice"
    },
    {
      "name": "Neutral Assistant",
      "voice_id": "eleven_labs_sam",
      "description": "Gender-neutral, clear voice"
    }
  ]
}
```

## Conversation Flow Configuration

### 1. Intent Recognition and Routing

#### Primary Intents
```json
{
  "intents": [
    {
      "name": "rent_inquiry",
      "patterns": [
        "rent payment",
        "balance",
        "how much do I owe",
        "payment history",
        "late fee"
      ],
      "response_template": "I can help you with rent-related questions. Let me look up your account information."
    },
    {
      "name": "maintenance_request",
      "patterns": [
        "repair",
        "broken",
        "not working",
        "maintenance",
        "fix",
        "leak",
        "heat",
        "air conditioning"
      ],
      "response_template": "I understand you need to report a maintenance issue. Can you describe the problem in detail?"
    },
    {
      "name": "lease_information",
      "patterns": [
        "lease",
        "contract",
        "renewal",
        "move out",
        "end date",
        "terms"
      ],
      "response_template": "I can provide information about your lease. What specific details would you like to know?"
    },
    {
      "name": "general_inquiry",
      "patterns": [
        "hours",
        "contact",
        "office",
        "manager",
        "complaint",
        "question"
      ],
      "response_template": "I'm here to help with your inquiry. Could you please provide more details?"
    }
  ]
}
```

### 2. Conversation Scripts

#### Greeting and Tenant Identification
```json
{
  "conversation_flow": {
    "greeting": {
      "message": "Hello! Thank you for calling [Property Name]. I'm your AI assistant. How can I help you today?",
      "next_step": "identify_tenant"
    },
    "identify_tenant": {
      "message": "To better assist you, could you please provide your name or the phone number associated with your account?",
      "input_type": "speech_to_text",
      "validation": "tenant_lookup",
      "success_path": "main_menu",
      "failure_path": "unknown_caller"
    },
    "unknown_caller": {
      "message": "I don't see that information in our system. Would you like me to connect you with a property manager, or would you prefer to call back during business hours?",
      "options": [
        {
          "text": "Connect to manager",
          "action": "transfer_call"
        },
        {
          "text": "Call back later",
          "action": "end_call_politely"
        }
      ]
    }
  }
}
```

#### Rent Payment Inquiries
```json
{
  "rent_inquiry_flow": {
    "balance_check": {
      "message": "Let me check your current balance. I see your account shows [BALANCE_AMOUNT]. Would you like to make a payment now or get more details about your payment history?",
      "dynamic_data": ["balance_amount", "last_payment_date", "due_date"],
      "options": [
        {
          "text": "Make payment",
          "action": "payment_process"
        },
        {
          "text": "Payment history",
          "action": "show_history"
        },
        {
          "text": "Something else",
          "action": "main_menu"
        }
      ]
    },
    "payment_process": {
      "message": "I can help you set up a payment. For security reasons, I'll need to transfer you to our secure payment system. Please hold while I connect you.",
      "action": "transfer_to_payment_system"
    }
  }
}
```

#### Maintenance Request Flow
```json
{
  "maintenance_flow": {
    "problem_description": {
      "message": "I understand you need to report a maintenance issue. Can you describe the problem? Please include the location in your unit and whether it's an emergency.",
      "input_type": "speech_to_text",
      "analysis": [
        "urgency_detection",
        "category_classification",
        "location_identification"
      ],
      "next_step": "urgency_assessment"
    },
    "urgency_assessment": {
      "emergency_keywords": [
        "flooding",
        "no heat",
        "no power",
        "gas leak",
        "fire",
        "security issue",
        "lock broken",
        "water damage"
      ],
      "urgent_response": "This sounds like an urgent issue. I'm creating a high-priority maintenance request and will notify our emergency maintenance team immediately. Is this correct?",
      "normal_response": "I've recorded your maintenance request. We typically respond to non-emergency requests within 24-48 hours. I'll send you a confirmation with your request number."
    }
  }
}
```

## Integration with n8n Workflows

### 1. Webhook Configuration

#### Retell AI to n8n Integration
```javascript
// n8n webhook endpoint configuration
const webhookConfig = {
  endpoint: "https://your-n8n-domain.com/webhook/retell-ai",
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer your-webhook-token"
  },
  events: [
    "call_started",
    "call_ended",
    "intent_recognized",
    "data_collected",
    "escalation_requested"
  ]
};

// Webhook payload structure
const webhookPayload = {
  call_id: "call_12345",
  caller_number: "+15551234567",
  intent: "maintenance_request",
  transcript: "I have a leaky faucet in my kitchen",
  extracted_data: {
    tenant_id: "T001",
    issue_type: "plumbing",
    location: "kitchen",
    urgency: "medium",
    description: "leaky faucet"
  },
  call_duration: 120,
  timestamp: "2024-01-15T10:30:00Z"
};
```

### 2. Data Exchange Format

#### Tenant Information Lookup
```json
{
  "request_type": "tenant_lookup",
  "lookup_criteria": {
    "phone_number": "+15551234567",
    "name": "John Smith"
  },
  "response_format": {
    "tenant_id": "T001",
    "name": "John Smith",
    "unit": "101",
    "property": "123 Main Street",
    "lease_end": "2024-12-31",
    "balance": 1250.00,
    "last_payment": "2024-01-01"
  }
}
```

#### Maintenance Request Submission
```json
{
  "request_type": "maintenance_request",
  "tenant_info": {
    "tenant_id": "T001",
    "name": "John Smith",
    "phone": "+15551234567",
    "unit": "101",
    "property": "123 Main Street"
  },
  "request_details": {
    "category": "plumbing",
    "description": "Kitchen faucet is leaking continuously",
    "location": "kitchen",
    "urgency": "medium",
    "reported_time": "2024-01-15T10:30:00Z"
  }
}
```

## Advanced Features Configuration

### 1. Sentiment Analysis
```json
{
  "sentiment_analysis": {
    "enabled": true,
    "escalation_threshold": -0.7,
    "monitoring_keywords": [
      "frustrated",
      "angry",
      "upset",
      "disappointed",
      "complaint",
      "unsatisfied"
    ],
    "escalation_message": "I understand your frustration. Let me connect you with a property manager who can better assist you with this situation."
  }
}
```

### 2. Multi-language Support
```json
{
  "language_support": {
    "primary_language": "en-US",
    "supported_languages": [
      {
        "code": "es-US",
        "name": "Spanish (US)",
        "detection_keywords": ["español", "habla español", "no english"]
      },
      {
        "code": "fr-CA",
        "name": "French (Canadian)",
        "detection_keywords": ["français", "parlez français"]
      }
    ],
    "language_switch_message": "I can switch to [LANGUAGE]. Please hold while I transfer you to our [LANGUAGE] assistant."
  }
}
```

### 3. Business Hours Handling
```json
{
  "business_hours": {
    "timezone": "America/New_York",
    "schedule": {
      "monday": {"open": "09:00", "close": "17:00"},
      "tuesday": {"open": "09:00", "close": "17:00"},
      "wednesday": {"open": "09:00", "close": "17:00"},
      "thursday": {"open": "09:00", "close": "17:00"},
      "friday": {"open": "09:00", "close": "17:00"},
      "saturday": {"open": "10:00", "close": "14:00"},
      "sunday": "closed"
    },
    "after_hours_message": "Thank you for calling. Our office is currently closed. Our business hours are Monday through Friday 9 AM to 5 PM, and Saturday 10 AM to 2 PM. For maintenance emergencies, please press 1 to be connected to our emergency line.",
    "emergency_transfer": {
      "enabled": true,
      "number": "+15551234567",
      "keywords": ["emergency", "urgent", "flooding", "no heat", "gas leak"]
    }
  }
}
```

## Quality Assurance and Monitoring

### 1. Call Quality Metrics
```json
{
  "quality_metrics": {
    "conversation_completion_rate": 0.85,
    "intent_recognition_accuracy": 0.92,
    "escalation_rate": 0.15,
    "average_call_duration": 180,
    "customer_satisfaction": 4.2,
    "resolution_rate": 0.78
  }
}
```

### 2. Performance Monitoring
```javascript
// Monitoring configuration
const monitoringConfig = {
  metrics_collection: {
    call_volume: true,
    response_time: true,
    error_rate: true,
    user_satisfaction: true
  },
  alerts: {
    high_error_rate: {
      threshold: 0.05,
      notification: "email"
    },
    low_satisfaction: {
      threshold: 3.0,
      notification: "slack"
    }
  }
};
```

## Testing and Validation

### 1. Test Scenarios
```json
{
  "test_scenarios": [
    {
      "name": "Rent Payment Inquiry",
      "input": "Hi, I want to check my rent balance",
      "expected_intent": "rent_inquiry",
      "expected_response": "I can help you with rent-related questions..."
    },
    {
      "name": "Emergency Maintenance",
      "input": "My apartment is flooding, I need help immediately",
      "expected_intent": "maintenance_request",
      "expected_urgency": "emergency",
      "expected_action": "immediate_escalation"
    },
    {
      "name": "Lease Renewal Question",
      "input": "When does my lease expire and how do I renew?",
      "expected_intent": "lease_information",
      "expected_response": "I can provide information about your lease..."
    }
  ]
}
```

### 2. Validation Checklist
- [ ] Voice quality and clarity
- [ ] Intent recognition accuracy
- [ ] Response appropriateness
- [ ] Data integration with n8n
- [ ] Escalation procedures
- [ ] Error handling
- [ ] Business hours compliance
- [ ] Multi-language support (if enabled)

## Security and Compliance

### 1. Data Privacy
```json
{
  "privacy_settings": {
    "call_recording": {
      "enabled": true,
      "consent_required": true,
      "retention_period": "12_months",
      "consent_message": "This call may be recorded for quality assurance purposes."
    },
    "data_encryption": {
      "in_transit": true,
      "at_rest": true,
      "key_rotation": "quarterly"
    },
    "pii_handling": {
      "detection": true,
      "masking": true,
      "retention_limit": "as_required_by_law"
    }
  }
}
```

### 2. Compliance Requirements
- TCPA compliance for automated calls
- Fair Housing Act compliance
- State and local privacy regulations
- Industry-specific requirements

This configuration guide provides the foundation for implementing Retell AI effectively in the Voice AI Property Management POC system. 