#!/bin/bash
apt-get install -y nginx
cp /app/nginx.conf /etc/nginx/nginx.conf
nginx
pnpm run pm2-run
