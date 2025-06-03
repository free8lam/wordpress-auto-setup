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
sudo apt update && sudo apt install -y docker.io docker-compose unzip curl

echo "📁 创建目录结构..."
mkdir -p wordpress-docker/{nginx/ssl,wp_data,db_data,php}
cd wordpress-docker || exit 1

echo "⚙️ 创建 php.ini..."
cat > php/php.ini <<EOF
upload_max_filesize = 1024M
post_max_size = 1024M
max_execution_time = 900
max_input_time = 900
EOF

echo "📄 创建 nginx 配置..."
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

echo "📄 创建 docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  wordpress:
    image: wordpress:php8.1-fpm
    volumes:
      - ./wp_data:/var/www/html
      - ./php/php.ini:/usr/local/etc/php/conf.d/uploads.ini
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: $DB_NAME
      WORDPRESS_DB_USER: $DB_USER
      WORDPRESS_DB_PASSWORD: $DB_PASS
    depends_on:
      - db
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
      --email $EMAIL --agree-tos --no-eff-email -d $DOMAIN
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
      - ./db_data:/var/lib/mysql
    networks:
      - wpnet

networks:
  wpnet:
EOF

echo "🚀 启动服务（第一次不申请证书）..."
docker-compose up -d

echo "⏳ 等待服务启动 20 秒..."
sleep 20

echo "🔐 申请 SSL 证书..."
docker-compose run --rm certbot

echo "🔁 重启 nginx..."
docker-compose restart nginx

echo "✅ 安装完成！请访问：https://$DOMAIN"
