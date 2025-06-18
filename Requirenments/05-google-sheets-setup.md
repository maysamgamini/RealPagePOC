# Google Sheets Setup Guide - Voice AI Property Management POC

## Overview
This document provides comprehensive guidance for setting up and configuring Google Sheets as the backend database for the Voice AI Property Management POC system, including sheet structure, API integration, automation formulas, and data management procedures.

## Google Sheets Architecture

### Database Structure Overview
```
Voice AI Property Management Database
├── Tenant Database (Main sheet)
├── Lease Information
├── Maintenance Requests
├── Payment History
├── Notice Log
├── Communication Log
├── Property Information
└── System Configuration
```

## Sheet Setup and Configuration

### 1. Tenant Database Sheet

#### Sheet Structure
```
| A | B | C | D | E | F | G | H | I | J | K |
|---|---|---|---|---|---|---|---|---|---|---|
| tenant_id | tenant_name | first_name | last_name | phone_number | email | property_address | unit_number | lease_start | lease_end | status |
| T001 | John Smith | John | Smith | 5551234567 | john@email.com | 123 Main St | 101 | 2023-01-01 | 2024-12-31 | Active |
| T002 | Jane Doe | Jane | Doe | 5559876543 | jane@email.com | 456 Oak Ave | 205 | 2023-03-15 | 2024-11-15 | Active |
```

#### Data Validation Rules
```javascript
// Phone number validation (Column E)
=AND(LEN(E2)=10, ISNUMBER(VALUE(E2)))

// Email validation (Column F)
=AND(FIND("@",F2)>1, FIND(".",F2,FIND("@",F2))>FIND("@",F2)+1)

// Date validation (Columns I and J)
=AND(ISDATE(I2), I2<J2)

// Status validation (Column K)
=OR(K2="Active", K2="Inactive", K2="Notice Given", K2="Moved Out")
```

#### Conditional Formatting
```javascript
// Highlight expiring leases (within 60 days)
=J2<=TODAY()+60

// Color code by status
// Active: Green background
// Notice Given: Yellow background  
// Moved Out: Red background
```

### 2. Lease Information Sheet

#### Sheet Structure
```
| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| lease_id | tenant_id | property_address | unit_number | lease_start | lease_end | monthly_rent | security_deposit | lease_type | renewal_option |
| L001 | T001 | 123 Main St | 101 | 2023-01-01 | 2024-12-31 | 1200 | 1200 | 12-month | Available |
| L002 | T002 | 456 Oak Ave | 205 | 2023-03-15 | 2024-11-15 | 1450 | 1450 | 12-month | Available |
```

#### Calculated Fields
```javascript
// Days remaining on lease (Column K)
=IF(J2>=TODAY(), J2-TODAY(), "Expired")

// Lease status (Column L)
=IF(J2>=TODAY()+60, "Active", IF(J2>=TODAY(), "Expiring Soon", "Expired"))

// Annual rent (Column M)
=G2*12
```

### 3. Maintenance Requests Sheet

#### Sheet Structure
```
| A | B | C | D | E | F | G | H | I | J | K | L |
|---|---|---|---|---|---|---|---|---|---|---|---|
| request_id | tenant_id | tenant_name | property_address | unit_number | request_type | description | urgency | status | date_submitted | date_completed | assigned_to |
| REQ-001 | T001 | John Smith | 123 Main St | 101 | Plumbing | Leaky faucet | Medium | Open | 2024-01-15 | | Mike Johnson |
| REQ-002 | T002 | Jane Doe | 456 Oak Ave | 205 | HVAC | No heat | High | Completed | 2024-01-10 | 2024-01-11 | Sarah Wilson |
```

#### Auto-Generated Request ID
```javascript
// Column A formula
=CONCATENATE("REQ-", TEXT(ROW()-1, "000"))
```

#### Status Tracking
```javascript
// Days since submitted (Column M)
=IF(K2="", TODAY()-J2, K2-J2)

// Priority scoring (Column N)
=IF(H2="Emergency", 4, IF(H2="High", 3, IF(H2="Medium", 2, 1)))
```

### 4. Payment History Sheet

#### Sheet Structure
```
| A | B | C | D | E | F | G | H | I |
|---|---|---|---|---|---|---|---|---|
| payment_id | tenant_id | tenant_name | payment_date | amount | payment_method | transaction_id | status | balance_after |
| PAY-001 | T001 | John Smith | 2024-01-01 | 1200.00 | Credit Card | TXN123456 | Completed | 0.00 |
| PAY-002 | T002 | Jane Doe | 2024-01-03 | 1450.00 | Bank Transfer | TXN789012 | Completed | 0.00 |
```

#### Balance Calculations
```javascript
// Running balance (Column I)
=SUMIFS(E:E, B:B, B2, D:D, "<="&D2) - SUMIFS(Charges[Amount], Charges[TenantID], B2, Charges[Date], "<="&D2)

// Payment status indicator (Column J)
=IF(I2<=0, "Paid in Full", IF(I2>0, "Balance Due: $"&I2, "Credit: $"&ABS(I2)))
```

### 5. 60-Day Notice Log Sheet

#### Sheet Structure
```
| A | B | C | D | E | F | G | H | I |
|---|---|---|---|---|---|---|---|---|
| notice_id | tenant_id | tenant_name | property_address | notice_date | lease_end_date | delivery_method | status | response_date |
| NOT-001 | T001 | John Smith | 123 Main St | 2024-10-31 | 2024-12-31 | Voice, Email, SMS | Sent | |
| NOT-002 | T003 | Bob Wilson | 789 Pine St | 2024-11-01 | 2024-12-31 | Voice, Email, SMS | Acknowledged | 2024-11-05 |
```

#### Automated Notice Detection
```javascript
// Formula to identify tenants needing 60-day notice
=IF(AND(Tenants[LeaseEnd]-TODAY()<=60, Tenants[LeaseEnd]-TODAY()>=59, Tenants[Status]="Active"), "Notice Required", "")
```

## Google Apps Script Integration

### 1. API Authentication Setup

#### Service Account Configuration
```javascript
// Code.gs - Authentication setup
function getAuthToken() {
  const serviceAccount = {
    "type": "service_account",
    "project_id": "your-project-id",
    "private_key_id": "your-private-key-id",
    "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n",
    "client_email": "your-service-account@your-project.iam.gserviceaccount.com",
    "client_id": "your-client-id",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  };
  
  const jwt = createJWT(serviceAccount);
  const token = exchangeJWTForAccessToken(jwt);
  return token;
}
```

### 2. n8n Integration Functions

#### Webhook Endpoints
```javascript
// Handle incoming tenant lookup requests
function doPost(e) {
  const requestData = JSON.parse(e.postData.contents);
  
  switch(requestData.action) {
    case 'tenant_lookup':
      return handleTenantLookup(requestData);
    case 'maintenance_request':
      return handleMaintenanceRequest(requestData);
    case 'payment_record':
      return handlePaymentRecord(requestData);
    case 'notice_log':
      return handleNoticeLog(requestData);
    default:
      return ContentService.createTextOutput(JSON.stringify({error: 'Unknown action'}))
        .setMimeType(ContentService.MimeType.JSON);
  }
}

// Tenant lookup function
function handleTenantLookup(requestData) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Tenant Database');
  const data = sheet.getDataRange().getValues();
  
  const phoneNumber = requestData.phone_number;
  
  for (let i = 1; i < data.length; i++) {
    if (data[i][4] === phoneNumber) { // Column E = phone_number
      const tenantInfo = {
        tenant_id: data[i][0],
        tenant_name: data[i][1],
        phone_number: data[i][4],
        email: data[i][5],
        property_address: data[i][6],
        unit_number: data[i][7],
        lease_end: data[i][9],
        status: data[i][10]
      };
      
      return ContentService.createTextOutput(JSON.stringify(tenantInfo))
        .setMimeType(ContentService.MimeType.JSON);
    }
  }
  
  return ContentService.createTextOutput(JSON.stringify({error: 'Tenant not found'}))
    .setMimeType(ContentService.MimeType.JSON);
}

// Maintenance request handler
function handleMaintenanceRequest(requestData) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Maintenance Requests');
  
  const newRow = [
    generateRequestId(),
    requestData.tenant_id,
    requestData.tenant_name,
    requestData.property_address,
    requestData.unit_number,
    requestData.request_type,
    requestData.description,
    requestData.urgency,
    'Open',
    new Date(),
    '',
    assignMaintenance(requestData.request_type)
  ];
  
  sheet.appendRow(newRow);
  
  // Send notifications if high priority
  if (requestData.urgency === 'High' || requestData.urgency === 'Emergency') {
    sendMaintenanceAlert(requestData);
  }
  
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    request_id: newRow[0]
  })).setMimeType(ContentService.MimeType.JSON);
}
```

### 3. Automated Workflows

#### Daily Lease Expiration Check
```javascript
function checkLeaseExpirations() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Tenant Database');
  const data = sheet.getDataRange().getValues();
  const today = new Date();
  const noticeDate = new Date(today.getTime() + (60 * 24 * 60 * 60 * 1000)); // 60 days from now
  
  const expiringLeases = [];
  
  for (let i = 1; i < data.length; i++) {
    const leaseEnd = new Date(data[i][9]); // Column J = lease_end
    const status = data[i][10]; // Column K = status
    
    if (leaseEnd <= noticeDate && status === 'Active') {
      expiringLeases.push({
        tenant_id: data[i][0],
        tenant_name: data[i][1],
        phone_number: data[i][4],
        email: data[i][5],
        property_address: data[i][6],
        unit_number: data[i][7],
        lease_end: data[i][9]
      });
    }
  }
  
  // Trigger n8n workflow for each expiring lease
  expiringLeases.forEach(tenant => {
    triggerNoticeWorkflow(tenant);
  });
  
  return expiringLeases.length;
}

// Trigger n8n 60-day notice workflow
function triggerNoticeWorkflow(tenantData) {
  const webhookUrl = 'https://your-n8n-domain.com/webhook/60-day-notice';
  
  const payload = {
    action: '60_day_notice',
    tenant_data: tenantData,
    notice_date: new Date().toISOString()
  };
  
  UrlFetchApp.fetch(webhookUrl, {
    method: 'POST',
    contentType: 'application/json',
    payload: JSON.stringify(payload)
  });
}
```

#### Rent Reminder Automation
```javascript
function sendRentReminders() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Tenant Database');
  const paymentSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Payment History');
  
  const tenants = sheet.getDataRange().getValues();
  const today = new Date();
  const reminderDate = new Date(today.getFullYear(), today.getMonth() + 1, 1); // First of next month
  
  for (let i = 1; i < tenants.length; i++) {
    if (tenants[i][10] === 'Active') { // Active tenants only
      const tenantId = tenants[i][0];
      const lastPayment = getLastPaymentDate(tenantId, paymentSheet);
      
      // Check if rent is due soon and no recent payment
      if (shouldSendReminder(lastPayment, reminderDate)) {
        const reminderData = {
          tenant_id: tenantId,
          tenant_name: tenants[i][1],
          phone_number: tenants[i][4],
          email: tenants[i][5],
          amount_due: tenants[i][11] || 0, // Assuming monthly rent in column L
          due_date: reminderDate.toISOString()
        };
        
        triggerRentReminderWorkflow(reminderData);
      }
    }
  }
}
```

## Data Management and Maintenance

### 1. Data Validation and Cleanup

#### Duplicate Detection
```javascript
function findDuplicateTenants() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Tenant Database');
  const data = sheet.getDataRange().getValues();
  const duplicates = [];
  
  for (let i = 1; i < data.length; i++) {
    for (let j = i + 1; j < data.length; j++) {
      if (data[i][4] === data[j][4] || data[i][5] === data[j][5]) { // Phone or email match
        duplicates.push({
          row1: i + 1,
          row2: j + 1,
          tenant1: data[i][1],
          tenant2: data[j][1],
          match_type: data[i][4] === data[j][4] ? 'phone' : 'email'
        });
      }
    }
  }
  
  return duplicates;
}
```

#### Data Backup
```javascript
function createBackup() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const backupName = `Backup_${Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd_HH-mm-ss')}`;
  
  const backup = ss.copy(backupName);
  
  // Move to backup folder
  const backupFolder = DriveApp.getFoldersByName('Property Management Backups').next();
  DriveApp.getFileById(backup.getId()).moveTo(backupFolder);
  
  return backup.getUrl();
}
```

### 2. Reporting and Analytics

#### Monthly Report Generation
```javascript
function generateMonthlyReport() {
  const report = {
    date: new Date(),
    tenant_count: getTenantCount(),
    maintenance_requests: getMaintenanceStats(),
    payment_summary: getPaymentSummary(),
    lease_expirations: getUpcomingExpirations()
  };
  
  // Create report sheet
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const reportSheet = ss.insertSheet(`Report_${Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM')}`);
  
  // Populate report data
  reportSheet.getRange('A1').setValue('Property Management Monthly Report');
  reportSheet.getRange('A3').setValue('Total Tenants:').getRange('B3').setValue(report.tenant_count);
  reportSheet.getRange('A4').setValue('Open Maintenance Requests:').getRange('B4').setValue(report.maintenance_requests.open);
  reportSheet.getRange('A5').setValue('Completed This Month:').getRange('B5').setValue(report.maintenance_requests.completed);
  
  return reportSheet.getUrl();
}
```

## Security and Access Control

### 1. Sheet Protection
```javascript
function protectSheets() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheets = ['Tenant Database', 'Payment History', 'Maintenance Requests'];
  
  sheets.forEach(sheetName => {
    const sheet = ss.getSheetByName(sheetName);
    const protection = sheet.protect();
    
    // Allow specific users to edit
    protection.addEditor('admin@property-company.com');
    protection.addEditor('manager@property-company.com');
    
    // Remove default editors
    protection.removeEditors(protection.getEditors());
    
    // Set warning message
    protection.setWarningOnly(false);
    protection.setDescription(`Protected sheet: ${sheetName}. Contact admin for access.`);
  });
}
```

### 2. Audit Trail
```javascript
function logDataChanges(e) {
  if (!e) return;
  
  const auditSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Audit Log');
  if (!auditSheet) return;
  
  const user = Session.getActiveUser().getEmail();
  const timestamp = new Date();
  const range = e.range;
  const oldValue = e.oldValue || '';
  const newValue = e.value || '';
  
  auditSheet.appendRow([
    timestamp,
    user,
    range.getSheet().getName(),
    range.getA1Notation(),
    oldValue,
    newValue
  ]);
}
```

## Integration Testing

### 1. API Endpoint Testing
```javascript
function testAPIEndpoints() {
  const tests = [
    {
      name: 'Tenant Lookup',
      payload: {action: 'tenant_lookup', phone_number: '5551234567'},
      expected: 'tenant_id'
    },
    {
      name: 'Maintenance Request',
      payload: {
        action: 'maintenance_request',
        tenant_id: 'T001',
        request_type: 'Plumbing',
        description: 'Test request',
        urgency: 'Medium'
      },
      expected: 'request_id'
    }
  ];
  
  const results = [];
  
  tests.forEach(test => {
    try {
      const response = doPost({postData: {contents: JSON.stringify(test.payload)}});
      const data = JSON.parse(response.getContent());
      
      results.push({
        test: test.name,
        success: data.hasOwnProperty(test.expected),
        response: data
      });
    } catch (error) {
      results.push({
        test: test.name,
        success: false,
        error: error.message
      });
    }
  });
  
  return results;
}
```

## Deployment Checklist

### Pre-Deployment
- [ ] Create Google Sheets database structure
- [ ] Set up service account and API credentials
- [ ] Configure data validation rules
- [ ] Implement conditional formatting
- [ ] Set up Google Apps Script functions
- [ ] Test API endpoints
- [ ] Configure sheet protection
- [ ] Set up automated backups

### Post-Deployment
- [ ] Verify n8n integration
- [ ] Test voice AI data flow
- [ ] Validate maintenance request workflow
- [ ] Test 60-day notice automation
- [ ] Monitor system performance
- [ ] Set up regular data maintenance
- [ ] Train users on system access

This Google Sheets setup guide provides a comprehensive foundation for implementing the database backend of the Voice AI Property Management POC system. 