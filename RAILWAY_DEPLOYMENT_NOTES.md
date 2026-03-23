# Postiz Railway Deployment - Troubleshooting Notes

**Date:** March 23, 2026
**Status:** Deployment working, login authentication issue pending

---

## Overview

Setting up self-hosted Postiz (social media scheduling tool) on Railway using a custom Docker configuration with nginx reverse proxy.

---

## Files Created/Modified

### 1. `nginx.conf` (root directory)

Reverse proxy configuration routing traffic through port 8080:
- `/api/*` → backend on `localhost:3000`
- `/` → frontend on `localhost:4200`
- `/uploads/` → static file serving

**Critical detail:** Must include all custom header passthroughs (`Auth`, `Reload`, `Onboarding`, `Activate`, `Showorg`, `Impersonate`, `Accept-Language`, `i18next`) - without these, authentication fails with 502 errors.

```nginx
worker_processes                auto;

events {
    worker_connections          1024;
}

http {
    include                     /etc/nginx/mime.types;
    default_type                application/octet-stream;
    sendfile                    on;
    access_log                  /var/log/nginx/access.log;
    client_max_body_size 2G;
    server {
        listen 8080;
        server_name _;
        gzip on;
        gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

        location /api/ {
            proxy_pass http://localhost:3000/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Reload $http_reload;
            proxy_set_header Onboarding $http_onboarding;
            proxy_set_header Activate $http_activate;
            proxy_set_header Auth $http_auth;
            proxy_set_header Showorg $http_showorg;
            proxy_set_header Impersonate $http_impersonate;
            proxy_set_header Accept-Language $http_accept_language;
        }

        location /uploads/ {
            alias /uploads/;
        }

        location / {
            proxy_pass http://localhost:4200/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Reload $http_reload;
            proxy_set_header Onboarding $http_onboarding;
            proxy_set_header Activate $http_activate;
            proxy_set_header Auth $http_auth;
            proxy_set_header Showorg $http_showorg;
            proxy_set_header Impersonate $http_impersonate;
            proxy_set_header Accept-Language $http_accept_language;
            proxy_set_header i18next $http_i18next;
        }
    }
}
```

### 2. `start.sh` (root directory)

Startup script that runs on container start:

```bash
#!/bin/bash
cp /app/nginx.conf /etc/nginx/nginx.conf
nginx

# Run prisma migrations
pnpm run prisma-db-push

# Unset Railway's PORT so backend uses 3000 from ecosystem config
unset PORT

# Start services with pm2 using ecosystem config
pm2 delete all || true
pm2 start ecosystem.config.js
pm2 logs
```

### 3. `ecosystem.config.js` (root directory)

PM2 process manager configuration - explicitly sets PORT=3000 for backend to avoid conflict with Railway's PORT variable:

```javascript
module.exports = {
  apps: [
    {
      name: 'backend',
      cwd: './apps/backend',
      script: 'pnpm',
      args: 'start',
      env: {
        PORT: 3000
      }
    },
    {
      name: 'frontend',
      cwd: './apps/frontend',
      script: 'pnpm',
      args: 'start'
    },
    {
      name: 'orchestrator',
      cwd: './apps/orchestrator',
      script: 'pnpm',
      args: 'start'
    }
  ]
};
```

### 4. `Dockerfile.dev` (modified)

Changed CMD to use our start.sh instead of the default pm2 workspace scripts:

```dockerfile
FROM node:22.20-bookworm-slim
ARG NEXT_PUBLIC_VERSION
ENV NEXT_PUBLIC_VERSION=$NEXT_PUBLIC_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    make \
    python3-pip \
    bash \
    nginx \
&& rm -rf /var/lib/apt/lists/*

RUN addgroup --system www \
 && adduser --system --ingroup www --home /www --shell /usr/sbin/nologin www \
 && mkdir -p /www \
 && chown -R www:www /www /var/lib/nginx

RUN npm --no-update-notifier --no-fund --global install pnpm@10.6.1 pm2

WORKDIR /app

COPY . /app

RUN pnpm install
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

# Copy our nginx config and make start.sh executable
COPY nginx.conf /app/nginx.conf
RUN chmod +x /app/start.sh

CMD ["bash", "/app/start.sh"]
```

---

## Railway Configuration

### Environment Variables Required

| Variable | Value | Notes |
|----------|-------|-------|
| `NEXT_PUBLIC_BACKEND_URL` | `https://your-app.railway.app/api` | Must include `/api` suffix and `https://` |
| `MAIN_URL` | `https://your-app.railway.app` | Must include `https://` |
| `FRONTEND_URL` | `https://your-app.railway.app` | Must include `https://` |
| `DATABASE_URL` | (auto from Railway Postgres) | Connection string |
| `JWT_SECRET` | (your secret) | For token signing |
| `REDIS_URL` | (if using Redis) | Optional |

### Networking Settings

- **Port:** `8080` (nginx listens here, Railway routes traffic to it)

### Build Settings

- **Builder:** Dockerfile
- **Dockerfile Path:** `Dockerfile.dev`

---

## Issues Encountered & Resolutions

### Issue 1: 502 Bad Gateway (Login button spinning forever)

**Cause:** Initial nginx.conf was missing critical header passthroughs, especially the `Auth` header.

**Fix:** Added all required headers from the original `var/docker/nginx.conf` to our custom nginx.conf.

---

### Issue 2: 502 continued after header fix

**Cause:** `NEXT_PUBLIC_BACKEND_URL` was missing the `/api` suffix.

**Fix:** Changed from `https://app.railway.app` to `https://app.railway.app/api`

---

### Issue 3: `EADDRINUSE: address already in use :::8080`

**Cause:** Railway sets `PORT=8080` environment variable. The backend was picking this up and trying to bind to 8080, but nginx was already listening on 8080.

**Attempted fixes that didn't work:**
- `export PORT=3000` in start.sh (Railway env var took precedence)
- ecosystem.config.js with env.PORT=3000 (pm2 workspace scripts were running instead)

**Final fix:**
1. Modified Dockerfile.dev CMD to `["bash", "/app/start.sh"]`
2. Added `unset PORT` in start.sh before starting pm2
3. ecosystem.config.js explicitly sets PORT=3000 for backend

---

### Issue 4: Configuration warnings in logs

**Warnings:** `MAIN_URL not set`, `FRONTEND_URL is not a valid URL`

**Fix:** Added `MAIN_URL` and ensured `FRONTEND_URL` includes `https://` prefix.

---

### Issue 5: Login button resets but doesn't work

**Cause:** No email provider configured - password reset emails don't send.

**Workaround:** Update password directly in database using bcrypt hash.

---

## Current Issue: Login Still Failing

### Symptoms
- Login button no longer spins forever (progress!)
- Button resets after clicking
- Error: "Invalid user name or password"
- Tried setting bcrypt hash directly in database

### Root Cause Analysis

The login query in `libraries/nestjs-libraries/src/database/prisma/users/users.repository.ts` filters by BOTH email AND `providerName`:

```typescript
getUserByEmail(email: string) {
  return this._user.model.user.findFirst({
    where: {
      email,
      providerName: Provider.LOCAL,  // <-- Must be LOCAL for email/password login
    },
    // ...
  });
}
```

### Required Database Fields for Login

For email/password login to work, the User record must have:

| Field | Required Value |
|-------|---------------|
| `email` | Your email address (exact match) |
| `providerName` | `LOCAL` (case-sensitive, not GOOGLE/GITHUB) |
| `activated` | `true` |
| `password` | bcrypt hash (e.g., `$2b$10$hw2GgOfNhqq1soNutoJg4ONkpwJ8FvJuNU4HNjMudky.yekylWRte` for password `Postiz123!`) |

### What to Check in Railway Postgres

1. Open Railway dashboard → Postgres service → Data tab
2. Find the `User` table
3. Locate your user record by email
4. Verify ALL THREE fields:
   - `providerName` = `LOCAL`
   - `activated` = `true` (checkbox)
   - `password` = bcrypt hash

**Important:** If the account was originally created via Google/GitHub OAuth, `providerName` will be `GOOGLE` or `GITHUB`. You must change it to `LOCAL` for email/password login.

---

## Generating a New bcrypt Hash

If you need a different password, use this Node.js script:

```javascript
const bcrypt = require('bcrypt');
const password = 'YourNewPassword123!';
const hash = bcrypt.hashSync(password, 10);
console.log(hash);
```

Or use an online bcrypt generator (set rounds to 10).

---

## Next Steps

1. **Verify database fields** - Check `providerName`, `activated`, and `password` in the User table
2. **If providerName is not LOCAL** - Change it to `LOCAL`
3. **If activated is false** - Change it to `true`
4. **Test login** with email and password `Postiz123!`

---

## Architecture Summary

```
Railway (port 8080)
       │
       ▼
    nginx (port 8080)
       │
       ├── /api/* ──────► backend (port 3000)
       │
       ├── /uploads/* ──► static files
       │
       └── /* ──────────► frontend (port 4200)
```

All three services (backend, frontend, orchestrator) run via PM2 inside a single container.

---

## Relevant Source Files

- Auth logic: `apps/backend/src/services/auth/auth.service.ts`
- User lookup: `libraries/nestjs-libraries/src/database/prisma/users/users.repository.ts`
- Password hashing: `libraries/helpers/src/auth/auth.service.ts`
- Prisma schema: `libraries/nestjs-libraries/src/database/prisma/schema.prisma`
