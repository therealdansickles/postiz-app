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
