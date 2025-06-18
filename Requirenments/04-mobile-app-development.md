# Mobile App Development Guide - Voice AI Property Management POC

## Overview
This document outlines the development of a companion mobile application for the Voice AI Property Management system, providing tenants with easy access to property management services through a user-friendly mobile interface.

## App Architecture

### Technology Stack
- **Frontend**: React Native (cross-platform iOS/Android)
- **Backend Integration**: REST API connections to n8n workflows
- **Authentication**: Firebase Auth or Auth0
- **Push Notifications**: Firebase Cloud Messaging
- **Database**: Local SQLite for offline capabilities
- **Voice Integration**: Native device speech recognition

### System Integration
```
┌─────────────────────────────────────────────────────────────┐
│                    Mobile App Architecture                  │
├─────────────────────────────────────────────────────────────┤
│  Mobile App → API Gateway → n8n Workflows → Backend Services│
│      ↓              ↓            ↓              ↓           │
│  Local Storage  Authentication  Voice AI    Google Sheets   │
│      ↓              ↓            ↓              ↓           │
│  Offline Mode   Push Notifications  Retell AI   Twilio     │
└─────────────────────────────────────────────────────────────┘
```

## Core Features

### 1. User Authentication and Profile

#### Login/Registration Flow
```javascript
// Authentication service
const AuthService = {
  login: async (email, password) => {
    try {
      const response = await firebase.auth().signInWithEmailAndPassword(email, password);
      return response.user;
    } catch (error) {
      throw new Error('Login failed: ' + error.message);
    }
  },
  
  register: async (email, password, tenantInfo) => {
    try {
      const userCredential = await firebase.auth().createUserWithEmailAndPassword(email, password);
      await userCredential.user.updateProfile({
        displayName: tenantInfo.name
      });
      
      // Link tenant account
      await linkTenantAccount(userCredential.user.uid, tenantInfo);
      return userCredential.user;
    } catch (error) {
      throw new Error('Registration failed: ' + error.message);
    }
  }
};
```

#### User Profile Management
```javascript
// Profile component
const ProfileScreen = () => {
  const [profile, setProfile] = useState({
    name: '',
    email: '',
    phone: '',
    unit: '',
    property: '',
    leaseEnd: ''
  });

  const updateProfile = async (updatedData) => {
    try {
      await api.put('/tenant/profile', updatedData);
      setProfile(updatedData);
      showSuccessMessage('Profile updated successfully');
    } catch (error) {
      showErrorMessage('Failed to update profile');
    }
  };

  return (
    <ScrollView style={styles.container}>
      <ProfileForm 
        profile={profile}
        onUpdate={updateProfile}
      />
    </ScrollView>
  );
};
```

### 2. Voice-Activated Features

#### Quick Voice Commands
```javascript
// Voice command service
const VoiceCommandService = {
  startListening: () => {
    Voice.start('en-US');
  },
  
  stopListening: () => {
    Voice.stop();
  },
  
  processCommand: (command) => {
    const intent = classifyIntent(command);
    
    switch(intent) {
      case 'rent_payment':
        navigateToRentPayment();
        break;
      case 'maintenance_request':
        navigateToMaintenanceRequest();
        break;
      case 'call_office':
        initiateVoiceCall();
        break;
      default:
        showVoiceHelp();
    }
  }
};

// Voice-activated maintenance request
const VoiceMaintenanceRequest = () => {
  const [isListening, setIsListening] = useState(false);
  const [transcript, setTranscript] = useState('');

  const startVoiceRequest = () => {
    setIsListening(true);
    Voice.start('en-US');
  };

  const submitVoiceRequest = async () => {
    try {
      const response = await api.post('/maintenance/voice-request', {
        transcript: transcript,
        timestamp: new Date().toISOString()
      });
      
      showSuccessMessage('Maintenance request submitted');
      navigation.navigate('MaintenanceHistory');
    } catch (error) {
      showErrorMessage('Failed to submit request');
    }
  };

  return (
    <View style={styles.container}>
      <TouchableOpacity 
        style={[styles.voiceButton, isListening && styles.listening]}
        onPress={startVoiceRequest}
      >
        <Icon name="microphone" size={50} color="#fff" />
        <Text style={styles.buttonText}>
          {isListening ? 'Listening...' : 'Tap to speak'}
        </Text>
      </TouchableOpacity>
      
      {transcript && (
        <View style={styles.transcriptContainer}>
          <Text style={styles.transcriptText}>{transcript}</Text>
          <Button title="Submit Request" onPress={submitVoiceRequest} />
        </View>
      )}
    </View>
  );
};
```

### 3. Rent Payment Integration

#### Payment Interface
```javascript
// Rent payment screen
const RentPaymentScreen = () => {
  const [paymentInfo, setPaymentInfo] = useState({
    balance: 0,
    dueDate: '',
    lastPayment: '',
    paymentHistory: []
  });

  const [paymentMethod, setPaymentMethod] = useState('card');

  useEffect(() => {
    loadPaymentInfo();
  }, []);

  const loadPaymentInfo = async () => {
    try {
      const response = await api.get('/tenant/payment-info');
      setPaymentInfo(response.data);
    } catch (error) {
      showErrorMessage('Failed to load payment information');
    }
  };

  const makePayment = async (amount, method) => {
    try {
      const response = await api.post('/tenant/make-payment', {
        amount: amount,
        method: method,
        timestamp: new Date().toISOString()
      });
      
      showSuccessMessage('Payment processed successfully');
      loadPaymentInfo(); // Refresh balance
    } catch (error) {
      showErrorMessage('Payment failed: ' + error.message);
    }
  };

  return (
    <ScrollView style={styles.container}>
      <Card style={styles.balanceCard}>
        <Text style={styles.balanceLabel}>Current Balance</Text>
        <Text style={styles.balanceAmount}>${paymentInfo.balance}</Text>
        <Text style={styles.dueDate}>Due: {paymentInfo.dueDate}</Text>
      </Card>

      <PaymentMethodSelector 
        selectedMethod={paymentMethod}
        onMethodChange={setPaymentMethod}
      />

      <Button 
        title={`Pay $${paymentInfo.balance}`}
        onPress={() => makePayment(paymentInfo.balance, paymentMethod)}
        style={styles.payButton}
      />

      <PaymentHistory history={paymentInfo.paymentHistory} />
    </ScrollView>
  );
};
```

### 4. Maintenance Request Management

#### Maintenance Request Form
```javascript
// Maintenance request form
const MaintenanceRequestForm = () => {
  const [request, setRequest] = useState({
    category: '',
    description: '',
    urgency: 'medium',
    location: '',
    images: []
  });

  const categories = [
    'Plumbing',
    'Electrical',
    'HVAC',
    'Appliances',
    'General Repair',
    'Emergency'
  ];

  const submitRequest = async () => {
    try {
      const formData = new FormData();
      formData.append('category', request.category);
      formData.append('description', request.description);
      formData.append('urgency', request.urgency);
      formData.append('location', request.location);
      
      // Add images
      request.images.forEach((image, index) => {
        formData.append(`image_${index}`, {
          uri: image.uri,
          type: image.type,
          name: `maintenance_${index}.jpg`
        });
      });

      const response = await api.post('/maintenance/request', formData, {
        headers: {
          'Content-Type': 'multipart/form-data'
        }
      });

      showSuccessMessage('Maintenance request submitted successfully');
      navigation.navigate('MaintenanceHistory');
    } catch (error) {
      showErrorMessage('Failed to submit request');
    }
  };

  return (
    <ScrollView style={styles.container}>
      <Picker
        selectedValue={request.category}
        onValueChange={(value) => setRequest({...request, category: value})}
      >
        {categories.map(category => (
          <Picker.Item key={category} label={category} value={category} />
        ))}
      </Picker>

      <TextInput
        style={styles.textInput}
        placeholder="Describe the issue in detail"
        multiline
        value={request.description}
        onChangeText={(text) => setRequest({...request, description: text})}
      />

      <UrgencySelector 
        selected={request.urgency}
        onSelect={(urgency) => setRequest({...request, urgency})}
      />

      <ImagePicker 
        images={request.images}
        onImagesChange={(images) => setRequest({...request, images})}
      />

      <Button 
        title="Submit Request"
        onPress={submitRequest}
        disabled={!request.category || !request.description}
      />
    </ScrollView>
  );
};
```

### 5. Communication Features

#### In-App Messaging
```javascript
// Messaging service
const MessagingService = {
  sendMessage: async (message) => {
    try {
      const response = await api.post('/messages/send', {
        message: message,
        timestamp: new Date().toISOString(),
        type: 'tenant_to_office'
      });
      return response.data;
    } catch (error) {
      throw new Error('Failed to send message');
    }
  },

  getMessages: async () => {
    try {
      const response = await api.get('/messages/history');
      return response.data;
    } catch (error) {
      throw new Error('Failed to load messages');
    }
  }
};

// Chat screen
const ChatScreen = () => {
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');

  const sendMessage = async () => {
    if (!newMessage.trim()) return;

    try {
      const message = await MessagingService.sendMessage(newMessage);
      setMessages([...messages, message]);
      setNewMessage('');
    } catch (error) {
      showErrorMessage('Failed to send message');
    }
  };

  return (
    <View style={styles.container}>
      <FlatList
        data={messages}
        renderItem={({item}) => <MessageBubble message={item} />}
        keyExtractor={item => item.id}
        style={styles.messagesList}
      />
      
      <View style={styles.inputContainer}>
        <TextInput
          style={styles.messageInput}
          value={newMessage}
          onChangeText={setNewMessage}
          placeholder="Type a message..."
          multiline
        />
        <TouchableOpacity onPress={sendMessage} style={styles.sendButton}>
          <Icon name="send" size={24} color="#007AFF" />
        </TouchableOpacity>
      </View>
    </View>
  );
};
```

### 6. Lease Management

#### Lease Information Display
```javascript
// Lease information screen
const LeaseInfoScreen = () => {
  const [leaseInfo, setLeaseInfo] = useState({
    startDate: '',
    endDate: '',
    monthlyRent: 0,
    deposit: 0,
    terms: [],
    renewalOptions: []
  });

  const [showRenewalOptions, setShowRenewalOptions] = useState(false);

  useEffect(() => {
    loadLeaseInfo();
  }, []);

  const loadLeaseInfo = async () => {
    try {
      const response = await api.get('/tenant/lease-info');
      setLeaseInfo(response.data);
      
      // Check if lease is expiring soon
      const daysUntilExpiration = calculateDaysUntilExpiration(response.data.endDate);
      if (daysUntilExpiration <= 90) {
        setShowRenewalOptions(true);
      }
    } catch (error) {
      showErrorMessage('Failed to load lease information');
    }
  };

  const requestRenewal = async (renewalType) => {
    try {
      await api.post('/tenant/renewal-request', {
        renewalType: renewalType,
        requestDate: new Date().toISOString()
      });
      
      showSuccessMessage('Renewal request submitted');
    } catch (error) {
      showErrorMessage('Failed to submit renewal request');
    }
  };

  return (
    <ScrollView style={styles.container}>
      <Card style={styles.leaseCard}>
        <Text style={styles.cardTitle}>Lease Information</Text>
        <InfoRow label="Start Date" value={leaseInfo.startDate} />
        <InfoRow label="End Date" value={leaseInfo.endDate} />
        <InfoRow label="Monthly Rent" value={`$${leaseInfo.monthlyRent}`} />
        <InfoRow label="Security Deposit" value={`$${leaseInfo.deposit}`} />
      </Card>

      {showRenewalOptions && (
        <Card style={styles.renewalCard}>
          <Text style={styles.cardTitle}>Renewal Options</Text>
          <Text style={styles.renewalText}>
            Your lease expires soon. Choose a renewal option:
          </Text>
          {leaseInfo.renewalOptions.map(option => (
            <TouchableOpacity
              key={option.id}
              style={styles.renewalOption}
              onPress={() => requestRenewal(option.type)}
            >
              <Text style={styles.optionTitle}>{option.title}</Text>
              <Text style={styles.optionDescription}>{option.description}</Text>
            </TouchableOpacity>
          ))}
        </Card>
      )}

      <LeaseTerms terms={leaseInfo.terms} />
    </ScrollView>
  );
};
```

## Push Notifications

### Notification Service
```javascript
// Push notification service
const NotificationService = {
  initialize: async () => {
    const token = await messaging().getToken();
    await api.post('/tenant/register-device', { token });
    
    // Handle foreground messages
    messaging().onMessage(async (remoteMessage) => {
      showInAppNotification(remoteMessage);
    });
    
    // Handle background messages
    messaging().setBackgroundMessageHandler(async (remoteMessage) => {
      console.log('Background message:', remoteMessage);
    });
  },

  scheduleLocalNotification: (title, body, date) => {
    PushNotification.localNotificationSchedule({
      title: title,
      message: body,
      date: date,
      playSound: true,
      soundName: 'default'
    });
  }
};

// Notification types
const NotificationTypes = {
  RENT_REMINDER: 'rent_reminder',
  MAINTENANCE_UPDATE: 'maintenance_update',
  LEASE_EXPIRATION: 'lease_expiration',
  GENERAL_ANNOUNCEMENT: 'general_announcement'
};
```

## Offline Capabilities

### Local Data Storage
```javascript
// Local storage service
const LocalStorageService = {
  storeData: async (key, data) => {
    try {
      await AsyncStorage.setItem(key, JSON.stringify(data));
    } catch (error) {
      console.error('Storage error:', error);
    }
  },

  getData: async (key) => {
    try {
      const data = await AsyncStorage.getItem(key);
      return data ? JSON.parse(data) : null;
    } catch (error) {
      console.error('Retrieval error:', error);
      return null;
    }
  },

  syncWithServer: async () => {
    try {
      const offlineData = await AsyncStorage.getItem('offline_data');
      if (offlineData) {
        const data = JSON.parse(offlineData);
        await api.post('/sync/offline-data', data);
        await AsyncStorage.removeItem('offline_data');
      }
    } catch (error) {
      console.error('Sync error:', error);
    }
  }
};
```

## Testing Strategy

### Unit Testing
```javascript
// Example test for payment service
describe('PaymentService', () => {
  test('should process payment successfully', async () => {
    const mockResponse = { success: true, transactionId: '12345' };
    api.post.mockResolvedValue({ data: mockResponse });

    const result = await PaymentService.makePayment(1000, 'card');
    
    expect(result.success).toBe(true);
    expect(result.transactionId).toBe('12345');
  });

  test('should handle payment failure', async () => {
    api.post.mockRejectedValue(new Error('Payment failed'));

    await expect(PaymentService.makePayment(1000, 'card'))
      .rejects.toThrow('Payment failed');
  });
});
```

### Integration Testing
```javascript
// Test API integration
describe('API Integration', () => {
  test('should authenticate user successfully', async () => {
    const response = await request(app)
      .post('/auth/login')
      .send({
        email: 'test@example.com',
        password: 'password123'
      })
      .expect(200);

    expect(response.body.token).toBeDefined();
  });
});
```

## Deployment

### Build Configuration
```javascript
// app.json
{
  "expo": {
    "name": "Property Management",
    "slug": "property-management",
    "version": "1.0.0",
    "platforms": ["ios", "android"],
    "ios": {
      "bundleIdentifier": "com.propertymanagement.app",
      "buildNumber": "1.0.0"
    },
    "android": {
      "package": "com.propertymanagement.app",
      "versionCode": 1
    },
    "notification": {
      "icon": "./assets/notification-icon.png",
      "color": "#000000"
    }
  }
}
```

### Release Process
```bash
# Build for iOS
expo build:ios --type app-store

# Build for Android
expo build:android --type app-bundle

# Deploy to app stores
expo upload:ios
expo upload:android
```

## Security Considerations

### Data Protection
- Encrypt sensitive data stored locally
- Use secure authentication tokens
- Implement certificate pinning
- Regular security audits

### Privacy Compliance
- Implement GDPR/CCPA compliance
- User consent management
- Data anonymization
- Right to be forgotten

This mobile app development guide provides a comprehensive foundation for creating a user-friendly companion app for the Voice AI Property Management POC system. 