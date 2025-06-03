#!/bin/bash

# ====== 用户自定义信息 ======
DOMAIN="x.golife.blog"
EMAIL="free8lam@gmail.com"
DB_NAME="free"
DB_USER="free"
DB_PASS="Lmh1980"
DB_ROOT_PASS="Lmh1980" # 建议与 DB_PASS 保持一致或更复杂
# ============================

echo "📦 更新系统并安装 Docker & Docker Compose..."
sudo apt update -y
sudo apt install -y docker.io docker-compose unzip curl

# 检查 Docker 是否安装成功
if ! command -v docker &> /dev/null
then
    echo "❌ Docker 安装失败，请检查您的系统环境或手动安装。"
    exit 1
fi

# 检查 Docker Compose 是否安装成功
if ! command -v docker-compose &> /dev/null
then
    echo "❌ Docker Compose 安装失败，请检查您的系统环境或手动安装。"
    exit 1
fi

echo "🔐 配置防火墙 (UFW) 开放必要端口..."
# 检查 UFW 是否存在，如果不存在则安装
if ! command -v ufw &> /dev/null
then
    echo "UFW 未安装，正在安装 UFW..."
    sudo apt install -y ufw
    if ! command -v ufw &> /dev/null
    then
        echo "❌ UFW 安装失败，请手动安装或配置防火墙。"
        # 不退出，因为可能用户会手动配置，但给出警告
    fi
fi

# 启用 UFW 并开放端口
if command -v ufw &> /dev/null
then
    sudo ufw allow 22/tcp comment 'Allow SSH' # 允许SSH连接
    sudo ufw allow 80/tcp comment 'Allow HTTP' # 允许HTTP
    sudo ufw allow 443/tcp comment 'Allow HTTPS' # 允许HTTPS

    # 启用 UFW，如果尚未启用
    if ! sudo ufw status | grep -q "Status: active"
    then
        echo "正在启用 UFW 防火墙..."
        sudo ufw --force enable
    else
        echo "UFW 防火墙已启用。"
    fi
    echo "防火墙端口 22, 80, 443 已开放。"
fi


echo "📁 创建目录结构..."
mkdir -p wordpress-docker/{nginx/ssl,wp_data,db_data,php}
cd wordpress-docker || { echo "❌ 无法进入 wordpress-docker 目录，脚本终止。"; exit 1; }

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

# 检查 Certbot 是否成功申请证书
if [ -f "./nginx/ssl/live/$DOMAIN/fullchain.pem" ]; then
    echo "✅ SSL 证书已成功申请。"
else
    echo "⚠️ SSL 证书申请失败。请检查 Certbot 输出及您的域名DNS配置。"
    echo "尝试手动启动 Nginx (无证书)并继续..."
    docker-compose restart nginx # 尝试重启 Nginx，即使没有证书也可能启动
    echo "您可能需要手动调试 Certbot 或配置 SSL。"
    echo "请访问 http://$DOMAIN 检查网站是否可达，然后手动解决证书问题。"
    exit 1 # 证书申请失败，脚本终止
fi


echo "🔁 重启 nginx 以加载 SSL 证书..."
docker-compose restart nginx

echo "🎉 安装完成！请访问：https://$DOMAIN"
echo "您现在可以开始配置您的 WordPress 网站了。"
echo "请记住：如果您的证书在 90 天后过期，您需要运行 'docker-compose run --rm certbot renew && docker-compose restart nginx' 来更新证书。"
