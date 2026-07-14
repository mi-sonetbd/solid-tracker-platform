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
});
