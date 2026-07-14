import * as Joi from 'joi';

export const environmentValidationSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'test', 'production').default('development'),
  APP_PORT: Joi.number().port().default(3000),
  DATABASE_URL: Joi.string()
    .uri({ scheme: ['postgres', 'postgresql'] })
    .required(),
  REDIS_URL: Joi.string()
    .uri({ scheme: ['redis', 'rediss'] })
    .required(),
  CORS_ORIGINS: Joi.string().allow('').default(''),
  TRACCAR_BASE_URL: Joi.string().uri().required(),
  TRACCAR_USERNAME: Joi.string().allow('').default(''),
  TRACCAR_PASSWORD: Joi.string().allow('').default(''),
  AUTH_JWT_ACCESS_SECRET: Joi.string().min(32).required(),
  AUTH_REFRESH_TOKEN_PEPPER: Joi.string().min(32).required(),
  AUTH_OTP_PEPPER: Joi.string().min(32).required(),
  AUTH_ACCESS_TOKEN_TTL_SECONDS: Joi.number().integer().min(60).default(900),
  AUTH_REFRESH_TOKEN_TTL_SECONDS: Joi.number().integer().min(3600).default(2592000),
  AUTH_MAX_FAILED_ATTEMPTS: Joi.number().integer().min(3).max(20).default(5),
  AUTH_LOCKOUT_SECONDS: Joi.number().integer().min(60).default(900),
  AUTH_LOGIN_IP_LIMIT: Joi.number().integer().min(1).default(20),
  AUTH_LOGIN_IP_WINDOW_SECONDS: Joi.number().integer().min(1).default(60),
  AUTH_LOGIN_MOBILE_LIMIT: Joi.number().integer().min(1).default(5),
  AUTH_LOGIN_MOBILE_WINDOW_SECONDS: Joi.number().integer().min(1).default(300),
  AUTH_OTP_TTL_SECONDS: Joi.number().integer().min(60).default(300),
  AUTH_OTP_MAX_ATTEMPTS: Joi.number().integer().min(3).max(20).default(5),
  BILLING_PAYOUT_ENCRYPTION_KEY: Joi.string().min(32).required(),
  TRACKING_CREDENTIAL_ENCRYPTION_KEY: Joi.string().min(32).required(),
  TRACKING_WEBHOOK_SECRET: Joi.string().min(32).required(),
  TRACKING_HTTP_TIMEOUT_MS: Joi.number().integer().min(1000).default(10000),
  PAYMENT_AUTOMATION_ENABLED: Joi.boolean().truthy('true').falsy('false').default(false),
  PAYMENT_AUTOMATION_INTERVAL_MS: Joi.number().integer().min(60000).default(60000),
  PAYMENT_AUTOMATION_BATCH_SIZE: Joi.number().integer().min(1).max(200).default(50),
  PAYMENT_AUTOMATION_DUE_IN_DAYS: Joi.number().integer().min(0).max(90).default(7),
  PAYMENT_GATEWAY_HTTP_TIMEOUT_MS: Joi.number().integer().min(1000).max(120000).default(15000),
  PAYMENT_CALLBACK_BASE_URL: Joi.string().uri().required(),
  PAYMENT_SANDBOX_WEBHOOK_SECRET: Joi.string().min(32).required(),
  BKASH_GATEWAY_PROXY_URL: Joi.string().allow('').default(''),
  BKASH_GATEWAY_PROXY_SECRET: Joi.string().allow('').default(''),
  NAGAD_GATEWAY_PROXY_URL: Joi.string().allow('').default(''),
  NAGAD_GATEWAY_PROXY_SECRET: Joi.string().allow('').default(''),
  SSLCOMMERZ_BASE_URL: Joi.string().allow('').default(''),
  SSLCOMMERZ_STORE_ID: Joi.string().allow('').default(''),
  SSLCOMMERZ_STORE_PASSWORD: Joi.string().allow('').default(''),
  NOTIFICATION_DELIVERY_ENABLED: Joi.boolean().truthy('true').falsy('false').default(false),
  NOTIFICATION_DELIVERY_INTERVAL_MS: Joi.number().integer().min(1000).max(3600000).default(5000),
  NOTIFICATION_DELIVERY_BATCH_SIZE: Joi.number().integer().min(1).max(200).default(25),
  NOTIFICATION_DELIVERY_MAX_ATTEMPTS: Joi.number().integer().min(1).max(20).default(5),
  NOTIFICATION_DELIVERY_RETRY_BASE_MS: Joi.number()
    .integer()
    .min(1000)
    .max(86400000)
    .default(30000),
  NOTIFICATION_PROVIDER_HTTP_TIMEOUT_MS: Joi.number()
    .integer()
    .min(1000)
    .max(120000)
    .default(10000),
  NOTIFICATION_CALLBACK_BASE_URL: Joi.string().uri().required(),
  NOTIFICATION_SANDBOX_WEBHOOK_SECRET: Joi.string().min(32).required(),
  NOTIFICATION_SMS_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_SMS_PROXY_SECRET: Joi.string().allow('').default(''),
  NOTIFICATION_EMAIL_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_EMAIL_PROXY_SECRET: Joi.string().allow('').default(''),
  NOTIFICATION_PUSH_PROXY_URL: Joi.string().allow('').default(''),
  NOTIFICATION_PUSH_PROXY_SECRET: Joi.string().allow('').default(''),
});
