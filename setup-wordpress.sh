{\rtf1\ansi\ansicpg936\cocoartf2822
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 #!/bin/bash\
\
# WordPress Docker \uc0\u19968 \u38190 \u37096 \u32626 \u33050 \u26412 \
# \uc0\u20316 \u32773 \u65306 \u20320 \u33258 \u24049 \u65288 GitHub \u29992 \u25143 \u21517 \u65289 \
# \uc0\u35831 \u22312 \u25191 \u34892 \u21069 \u20462 \u25913  DOMAIN \u21644  EMAIL \u21464 \u37327 \
\
# ====== \uc0\u29992 \u25143 \u38656 \u35201 \u20462 \u25913 \u30340 \u37096 \u20998  ======\
DOMAIN="yourdomain.com"        # <<< \uc0\u35831 \u20462 \u25913 \u65306 \u20320 \u30340 \u22495 \u21517 \
EMAIL="you@example.com"        # <<< \uc0\u35831 \u20462 \u25913 \u65306 \u20320 \u30340 \u37038 \u31665 \
# =================================\
\
# \uc0\u23433 \u35013 \u20381 \u36182 \
echo "\uc0\u55357 \u56550  \u23433 \u35013  Docker & Docker Compose..."\
sudo apt update\
sudo apt install -y docker.io docker-compose unzip curl\
\
# \uc0\u21019 \u24314 \u30446 \u24405 \u32467 \u26500 \
echo "\uc0\u55357 \u56513  \u21019 \u24314 \u30446 \u24405  wordpress-docker..."\
mkdir -p wordpress-docker/\{php,nginx,wp_data,nginx/ssl\}\
cd wordpress-docker || exit 1\
\
# \uc0\u19979 \u36733 \u20013 \u25991  WordPress\
echo "\uc0\u11015 \u65039  \u19979 \u36733  WordPress \u20013 \u25991 \u29256 ..."\
wget https://cn.wordpress.org/latest-zh_CN.zip -O wordpress.zip\
unzip wordpress.zip\
mv wordpress/* wp_data/\
rm -rf wordpress wordpress.zip\
\
# \uc0\u21019 \u24314  Dockerfile\u65288 PHP \u23481 \u22120 \u65289 \
cat > php/Dockerfile <<EOF\
FROM wordpress:php8.1-fpm\
\
RUN apt-get update && apt-get install -y \\\\\
    libpng-dev libjpeg-dev libfreetype6-dev \\\\\
    libzip-dev zip unzip libonig-dev \\\\\
 && docker-php-ext-configure gd --with-freetype --with-jpeg \\\\\
 && docker-php-ext-install gd mbstring zip mysqli pdo pdo_mysql xml curl\
\
RUN echo "upload_max_filesize=1024M" > /usr/local/etc/php/conf.d/uploads.ini && \\\\\
    echo "post_max_size=1024M" >> /usr/local/etc/php/conf.d/uploads.ini && \\\\\
    echo "max_execution_time=900" >> /usr/local/etc/php/conf.d/uploads.ini && \\\\\
    echo "max_input_time=900" >> /usr/local/etc/php/conf.d/uploads.ini\
EOF\
\
# \uc0\u21019 \u24314  Nginx \u37197 \u32622 \
cat > nginx/default.conf <<EOF\
server \{\
    listen 80;\
    server_name $DOMAIN;\
\
    location /.well-known/acme-challenge/ \{\
        root /var/www/html;\
    \}\
\
    location / \{\
        return 301 https://\\$host\\$request_uri;\
    \}\
\}\
\
server \{\
    listen 443 ssl;\
    server_name $DOMAIN;\
\
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;\
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;\
\
    client_max_body_size 1024M;\
\
    root /var/www/html;\
    index index.php index.html;\
\
    location / \{\
        try_files \\$uri \\$uri/ /index.php?\\$args;\
    \}\
\
    location ~ \\.php\\$ \{\
        fastcgi_pass wordpress:9000;\
        include fastcgi_params;\
        fastcgi_param SCRIPT_FILENAME /var/www/html\\$fastcgi_script_name;\
    \}\
\}\
EOF\
\
# \uc0\u21019 \u24314  docker-compose.yml\
cat > docker-compose.yml <<EOF\
version: '3.8'\
\
services:\
  wordpress:\
    build: ./php\
    volumes:\
      - ./wp_data:/var/www/html\
    networks:\
      - wpnet\
\
  nginx:\
    image: nginx:alpine\
    ports:\
      - "80:80"\
      - "443:443"\
    volumes:\
      - ./wp_data:/var/www/html\
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf\
      - ./nginx/ssl:/etc/letsencrypt\
    depends_on:\
      - wordpress\
    networks:\
      - wpnet\
\
  certbot:\
    image: certbot/certbot\
    volumes:\
      - ./nginx/ssl:/etc/letsencrypt\
      - ./wp_data:/var/www/html\
    command: >\
      certonly --webroot --webroot-path=/var/www/html\
      --email $EMAIL\
      --agree-tos --no-eff-email\
      -d $DOMAIN\
    networks:\
      - wpnet\
\
  db:\
    image: mysql:5.7\
    restart: always\
    environment:\
      MYSQL_ROOT_PASSWORD:rootpass\
      MYSQL_DATABASE:wp\
      MYSQL_USER:wpuser\
      MYSQL_PASSWORD:wppass\
    volumes:\
      - db_data:/var/lib/mysql\
    networks:\
      - wpnet\
\
networks:\
  wpnet:\
\
volumes:\
  db_data:\
EOF\
\
# \uc0\u21551 \u21160 \u26381 \u21153 \
echo "\uc0\u55357 \u56960  \u21551 \u21160  Docker \u26381 \u21153 ..."\
docker-compose up -d --build\
\
sleep 10\
\
# \uc0\u33719 \u21462  SSL \u35777 \u20070 \
echo "\uc0\u55357 \u56592  \u27491 \u22312 \u33719 \u21462  SSL \u35777 \u20070 ..."\
docker-compose run --rm certbot\
\
# \uc0\u37325 \u21551  nginx \u21152 \u36733 \u35777 \u20070 \
echo "\uc0\u55357 \u56577  \u37325 \u21551  Nginx..."\
docker-compose restart nginx\
\
echo "\uc0\u9989  \u23433 \u35013 \u23436 \u25104 \u65281 \u35831 \u35775 \u38382  https://$DOMAIN"}