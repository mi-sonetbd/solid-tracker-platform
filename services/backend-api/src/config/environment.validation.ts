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
});
