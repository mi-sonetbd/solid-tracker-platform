# syntax=docker/dockerfile:1.7
FROM node:24-alpine AS build

ARG PNPM_VERSION=11.12.0

RUN apk add --no-cache openssl \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY services/backend-api/package.json ./services/backend-api/package.json

RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm config set store-dir /pnpm/store \
    && pnpm config set fetch-retries 5 \
    && pnpm config set fetch-retry-mintimeout 20000 \
    && pnpm config set fetch-retry-maxtimeout 120000 \
    && pnpm config set fetch-timeout 600000 \
    && pnpm install --frozen-lockfile --filter @solid-tracker/backend-api...

COPY services/backend-api ./services/backend-api

RUN DATABASE_URL=postgresql://build:build@127.0.0.1:5432/build \
    pnpm --filter @solid-tracker/backend-api build

FROM node:24-alpine AS runtime

ARG PNPM_VERSION=11.12.0

RUN apk add --no-cache openssl \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

ENV NODE_ENV=production

WORKDIR /app

COPY --from=build --chown=node:node /app /app

USER node
WORKDIR /app/services/backend-api

EXPOSE 3000

CMD ["sh", "-c", "pnpm exec prisma migrate deploy --config prisma.config.ts && node dist/src/main.js"]
