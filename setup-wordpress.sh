#!/bin/bash

# WordPress Docker 一键部署脚本
# 作者：你自己（GitHub 用户名）
# 请在执行前修改 DOMAIN 和 EMAIL 变量

# ====== 用户需要修改的部分 ======
DOMAIN="yourdomain.com"        # <<< 请修改：你的域名
EMAIL="you@example.com"        # <<< 请修改：你的邮箱
# =================================

# 安装依赖
echo "📦 安装 Docker & Docker Compose..."
sudo apt update
sudo apt install -y docker.io docker-compose unzip curl

# 创建目录结构
echo "📁 创建目录 wordpress-docker..."
mkdir -p wordpress-docker/{php,nginx,wp_data,nginx/ssl}
cd wordpress-docker || exit 1

# 下载中文 WordPress
echo "⬇️ 下载 WordPress 中文版..."
wget https://cn.wordpress.org/latest-zh_CN.zip -O wordpress.zip
unzip wordpress.zip
mv wordpress/* wp_data/
rm -rf wordpress wordpress.zip

# 创建 Dockerfile（PHP 容器）
cat > php/Dockerfile <<EOF
FROM wordpress:php8.1-fpm

RUN apt-get update && apt-get install -y \\
    libpng-dev libjpeg-dev libfreetype6-dev \\
    libzip-dev zip unzip libonig-dev \\
 && docker-php-ext-configure gd --with-freetype --with-jpeg \\
 && docker-php-ext-install gd mbstring zip mysqli pdo pdo_mysql xml curl

RUN echo "upload_max_filesize=1024M" > /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "post_max_size=1024M" >> /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "max_execution_time=900" >> /usr/local/etc/php/conf.d/uploads.ini && \\
    echo "max_input_time=900" >> /usr/local/etc/php/conf.d/uploads.ini
EOF

# 创建 Nginx 配置
cat > nginx/default.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
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

# 创建 docker-compose.yml
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
      MYSQL_ROOT_PASSWORD:rootpass
      MYSQL_DATABASE:wp
      MYSQL_USER:wpuser
      MYSQL_PASSWORD:wppass
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - wpnet

networks:
  wpnet:

volumes:
  db_data:
EOF

# 启动服务
echo "🚀 启动 Docker 服务..."
docker-compose up -d --build

sleep 10

# 获取 SSL 证书
echo "🔐 正在获取 SSL 证书..."
docker-compose run --rm certbot

# 重启 nginx 加载证书
echo "🔁 重启 Nginx..."
docker-compose restart nginx

echo "✅ 安装完成！请访问 https://$DOMAIN"