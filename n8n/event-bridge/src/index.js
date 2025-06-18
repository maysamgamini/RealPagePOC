const express = require('express');
const Redis = require('ioredis');
const axios = require('axios');
const winston = require('winston');
const helmet = require('helmet');
const compression = require('compression');
const cors = require('cors');
const client = require('prom-client');
require('dotenv').config();

// Prometheus metrics
const register = new client.Registry();
const eventsProcessedCounter = new client.Counter({
  name: 'eventbridge_events_processed_total',
  help: 'Total number of events processed',
  labelNames: ['stream', 'status']
});
const webhookCallsCounter = new client.Counter({
  name: 'eventbridge_webhook_calls_total',
  help: 'Total number of webhook calls made',
  labelNames: ['status']
});
const redisConnectionGauge = new client.Gauge({
  name: 'eventbridge_redis_connection_status',
  help: 'Redis connection status (1 = connected, 0 = disconnected)'
});

register.registerMetric(eventsProcessedCounter);
register.registerMetric(webhookCallsCounter);
register.registerMetric(redisConnectionGauge);

// Logger configuration
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// Configuration
const config = {
  redis: {
    host: process.env.REDIS_HOST || 'redis-master',
    port: parseInt(process.env.REDIS_PORT) || 6379,
    password: process.env.REDIS_PASSWORD || '',
    db: parseInt(process.env.REDIS_DB) || 0,
    retryDelayOnFailover: 100,
    maxRetriesPerRequest: 3,
    lazyConnect: true
  },
  n8n: {
    webhookUrl: process.env.N8N_WEBHOOK_URL || 'http://n8n-main:5678/webhook',
    timeout: parseInt(process.env.N8N_TIMEOUT) || 10000
  },
  streams: {
    names: (process.env.STREAM_NAMES || 'retell-events,twilio-events,property-events').split(','),
    consumerGroup: process.env.CONSUMER_GROUP || 'n8n-event-bridge',
    consumerId: process.env.CONSUMER_ID || `consumer-${process.pid}`,
    blockTime: parseInt(process.env.BLOCK_TIME) || 5000,
    count: parseInt(process.env.COUNT) || 10
  },
  server: {
    port: parseInt(process.env.PORT) || 8080
  }
};

class EventBridge {
  constructor() {
    this.redis = new Redis(config.redis);
    this.isRunning = false;
    this.consumerPromises = [];
    
    this.setupRedisEventHandlers();
  }

  setupRedisEventHandlers() {
    this.redis.on('connect', () => {
      logger.info('Connected to Redis');
      redisConnectionGauge.set(1);
    });

    this.redis.on('error', (error) => {
      logger.error('Redis connection error:', error);
      redisConnectionGauge.set(0);
    });

    this.redis.on('close', () => {
      logger.warn('Redis connection closed');
      redisConnectionGauge.set(0);
    });
  }

  async initialize() {
    try {
      await this.redis.connect();
      
      // Create consumer groups for each stream
      for (const streamName of config.streams.names) {
        try {
          await this.redis.xgroup('CREATE', streamName, config.streams.consumerGroup, '$', 'MKSTREAM');
          logger.info(`Created consumer group for stream: ${streamName}`);
        } catch (error) {
          if (error.message.includes('BUSYGROUP')) {
            logger.info(`Consumer group already exists for stream: ${streamName}`);
          } else {
            throw error;
          }
        }
      }
      
      logger.info('Event Bridge initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize Event Bridge:', error);
      throw error;
    }
  }

  async startConsumers() {
    this.isRunning = true;
    
    // Start consumer for each stream
    for (const streamName of config.streams.names) {
      const consumerPromise = this.consumeStream(streamName);
      this.consumerPromises.push(consumerPromise);
    }
    
    logger.info(`Started consumers for ${config.streams.names.length} streams`);
  }

  async consumeStream(streamName) {
    logger.info(`Starting consumer for stream: ${streamName}`);
    
    while (this.isRunning) {
      try {
        const results = await this.redis.xreadgroup(
          'GROUP',
          config.streams.consumerGroup,
          config.streams.consumerId,
          'COUNT',
          config.streams.count,
          'BLOCK',
          config.streams.blockTime,
          'STREAMS',
          streamName,
          '>'
        );

        if (results && results.length > 0) {
          for (const [stream, messages] of results) {
            for (const [messageId, fields] of messages) {
              await this.processMessage(stream, messageId, fields);
            }
          }
        }
      } catch (error) {
        if (this.isRunning) {
          logger.error(`Error consuming stream ${streamName}:`, error);
          await this.sleep(1000); // Wait before retrying
        }
      }
    }
  }

  async processMessage(streamName, messageId, fields) {
    try {
      logger.info(`Processing message ${messageId} from stream ${streamName}`);
      
      // Convert fields array to object
      const event = this.fieldsToObject(fields);
      
      // Enrich event with metadata
      const enrichedEvent = {
        ...event,
        _metadata: {
          streamName,
          messageId,
          timestamp: new Date().toISOString(),
          consumerId: config.streams.consumerId
        }
      };
      
      // Send to n8n webhook
      await this.sendToWebhook(streamName, enrichedEvent);
      
      // Acknowledge message
      await this.redis.xack(streamName, config.streams.consumerGroup, messageId);
      
      eventsProcessedCounter.inc({ stream: streamName, status: 'success' });
      logger.info(`Successfully processed message ${messageId} from stream ${streamName}`);
      
    } catch (error) {
      logger.error(`Failed to process message ${messageId} from stream ${streamName}:`, error);
      eventsProcessedCounter.inc({ stream: streamName, status: 'error' });
      
      // Optionally implement dead letter queue or retry logic here
    }
  }

  async sendToWebhook(streamName, event) {
    const webhookPath = this.getWebhookPath(streamName);
    const webhookUrl = `${config.n8n.webhookUrl}${webhookPath}`;
    
    try {
      const response = await axios.post(webhookUrl, event, {
        timeout: config.n8n.timeout,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'n8n-event-bridge/1.0.0'
        }
      });
      
      webhookCallsCounter.inc({ status: 'success' });
      logger.debug(`Webhook call successful: ${webhookUrl}`, { status: response.status });
      
    } catch (error) {
      webhookCallsCounter.inc({ status: 'error' });
      logger.error(`Webhook call failed: ${webhookUrl}`, error.message);
      throw error;
    }
  }

  getWebhookPath(streamName) {
    // Map stream names to webhook paths
    const pathMapping = {
      'retell-events': '/retell-stream',
      'twilio-events': '/twilio-stream',
      'property-events': '/property-stream'
    };
    
    return pathMapping[streamName] || `/${streamName}`;
  }

  fieldsToObject(fields) {
    const obj = {};
    for (let i = 0; i < fields.length; i += 2) {
      obj[fields[i]] = fields[i + 1];
    }
    return obj;
  }

  async stop() {
    logger.info('Stopping Event Bridge...');
    this.isRunning = false;
    
    // Wait for all consumers to finish
    await Promise.all(this.consumerPromises);
    
    // Close Redis connection
    await this.redis.quit();
    
    logger.info('Event Bridge stopped');
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Express app for health checks and metrics
const app = express();

app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    // Check Redis connection
    await eventBridge.redis.ping();
    
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      redis: 'connected'
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Stream status endpoint
app.get('/streams', async (req, res) => {
  try {
    const streamInfo = {};
    
    for (const streamName of config.streams.names) {
      const info = await eventBridge.redis.xinfo('STREAM', streamName);
      streamInfo[streamName] = {
        length: info[1],
        firstEntry: info[5],
        lastEntry: info[7]
      };
    }
    
    res.json(streamInfo);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Initialize and start
const eventBridge = new EventBridge();

async function main() {
  try {
    await eventBridge.initialize();
    await eventBridge.startConsumers();
    
    app.listen(config.server.port, () => {
      logger.info(`Event Bridge server listening on port ${config.server.port}`);
    });
    
  } catch (error) {
    logger.error('Failed to start Event Bridge:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  logger.info('Received SIGINT, shutting down gracefully...');
  await eventBridge.stop();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  logger.info('Received SIGTERM, shutting down gracefully...');
  await eventBridge.stop();
  process.exit(0);
});

if (require.main === module) {
  main();
}

module.exports = EventBridge; 