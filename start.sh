#!/bin/bash
cp /app/nginx.conf /etc/nginx/nginx.conf
nginx

# Run prisma migrations
pnpm run prisma-db-push

# Start services with pm2 using ecosystem config (sets PORT=3000 for backend)
pm2 delete all || true
pm2 start ecosystem.config.js
pm2 logs
