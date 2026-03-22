#!/bin/bash
cp /app/nginx.conf /etc/nginx/nginx.conf
nginx

# Override PORT so backend runs on 3000 (nginx proxies to this)
export PORT=3000

pnpm run pm2-run
