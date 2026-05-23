FROM webdevops/php-nginx:8.1-alpine

ENV WEB_DOCUMENT_ROOT=/acg-faka \
    OPCACHE_FILE_CACHE_DIR=/app/opcache_cache_dir \
    PHP_INI_FILE=/opt/docker/etc/php/php.ini \
    TIMEZONE=Asia/Shanghai

RUN git clone --depth=1 https://github.com/lizhipay/acg-faka.git /acg-faka \
    && rm -rf /acg-faka/.git

WORKDIR /acg-faka

RUN composer install --no-dev --prefer-dist --optimize-autoloader \
    && composer clear-cache

RUN mkdir -p "$OPCACHE_FILE_CACHE_DIR" \
    && chown -R application:application "$OPCACHE_FILE_CACHE_DIR" \
    && { \
        echo "[opcache]"; \
        echo "opcache.enable=1"; \
        echo "opcache.memory_consumption=192"; \
        echo "opcache.interned_strings_buffer=16"; \
        echo "opcache.max_accelerated_files=10000"; \
        echo "opcache.revalidate_freq=5"; \
        echo "opcache.save_comments=1"; \
        echo "opcache.file_cache=${OPCACHE_FILE_CACHE_DIR}"; \
        echo "opcache.file_cache_only=0"; \
        echo "date.timezone=${TIMEZONE}"; \
    } >> "$PHP_INI_FILE"

RUN cat > /opt/docker/etc/nginx/vhost.conf <<'EOF'
server {
    listen 80;
    server_name _;

    root /acg-faka;
    index index.php;

    client_max_body_size 50m;

    location / {
        if (!-e $request_filename) {
            rewrite ^(.*)$ /index.php?s=$1 last;
            break;
        }
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~* \.(css|js|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 5;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;
}
EOF

RUN chown -R application:application /acg-faka \
    && chmod -R 755 /acg-faka
