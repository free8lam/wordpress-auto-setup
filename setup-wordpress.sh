#!/bin/bash

# ====== 用户自定义信息 ======
DOMAIN="x.golife.blog"
EMAIL="free8lam@gmail.com"
DB_NAME="free8lam"
DB_USER="free8lam"
DB_PASS="Lmh888999**##"
DB_ROOT_PASS="Lmh8889998833"
# ============================

echo "📦 安装 Docker & Docker Compose..."
sudo apt update
sudo apt install -y docker.io docker-compose unzip curl

echo "📁 创建目录 wordpress-docker..."
mkdir -p wordpress-docker/{php,nginx,wp_data,nginx/ssl}
cd wordpress-docker || exit 1

echo "⬇️ 下载 WordPress 英文版..."
wget https://wordpress.org/latest.zip -O wordpress.zip
unzip wordpress.zip
mv wordpress/* wp_data/
rm -rf wordpress wordpress.zip

echo "📄 创建 PHP Dockerfile..."
cat > php/Dockerfile <<EOF
FROM wordpress:php8.1-fpm

RUN apt-get update && apt-get install -y \\
    pkg-config libpng-dev libjpeg-dev libfreetype6-dev \\
    libwebp-dev libzip-dev zip unzip libonig-dev libxml2-dev \\
 && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \\
 && docker-php-ext-install gd mbstring zip mysqli pdo pdo_mysql xml curl

RUN echo "upload_max_filesize=1024M" > /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "post_max_size=1024M" >> /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "max_execution_time=900" >> /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "max_input_time=900" >> /usr/local/etc/php/conf.d/uploads.ini
EOF

echo "📄 创建 nginx 配置 (仅 HTTP 阶段)..."
cat > nginx/default.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass wordpress:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /var/www/html\$fastcgi_script_name;
    }
}
EOF

echo "📄 创建 docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  wordpress:
    build: ./php
    volumes:
      - ./wp_data:/var/www/html
    networks:
      - wpnet

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./wp_data:/var/www/html
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/ssl:/etc/letsencrypt
    depends_on:
      - wordpress
    networks:
      - wpnet

  certbot:
    image: certbot/certbot
    volumes:
      - ./nginx/ssl:/etc/letsencrypt
      - ./wp_data:/var/www/html
    command: >
      certonly --webroot --webroot-path=/var/www/html
      --email $EMAIL
      --agree-tos --no-eff-email
      -d $DOMAIN
    networks:
      - wpnet

  db:
    image: mysql:5.7
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $DB_ROOT_PASS
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASS
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wpnet

networks:
  wpnet:

volumes:
  db_data:
EOF

echo "🚀 构建容器（首次启动，仅 HTTP）..."
docker-compose up -d --build

sleep 15

echo "🔐 获取 SSL 证书..."
docker-compose run --rm certbot

echo "🔄 更新 nginx 配置为 HTTPS..."
cat > nginx/default.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    client_max_body_size 1024M;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass wordpress:9000;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /var/www/html\$fastcgi_script_name;
    }
}
EOF

echo "🔁 重启 nginx..."
docker-compose restart nginx

echo "✅ WordPress 已安装并启用 HTTPS，请访问: https://$DOMAIN"
