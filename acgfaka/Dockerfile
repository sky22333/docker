FROM php:8.1-fpm-alpine

ENV APP_DIR=/acg-faka \
    OPCACHE_FILE_CACHE_DIR=/app/opcache_cache_dir \
    TIMEZONE=Asia/Shanghai

RUN apk add --no-cache \
        nginx \
        git \
        unzip \
        curl \
        icu-dev \
        oniguruma-dev \
        libzip-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        mysqli \
        mbstring \
        bcmath \
        intl \
        zip \
        gd \
        opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN git clone --depth=1 https://github.com/lizhipay/acg-faka.git "$APP_DIR" \
    && rm -rf "$APP_DIR/.git"

WORKDIR $APP_DIR

RUN composer install --no-dev --prefer-dist --optimize-autoloader \
    && composer clear-cache

RUN mkdir -p "$OPCACHE_FILE_CACHE_DIR" \
    && chown -R www-data:www-data "$OPCACHE_FILE_CACHE_DIR" \
    && { \
        echo "opcache.enable=1"; \
        echo "opcache.memory_consumption=192"; \
        echo "opcache.interned_strings_buffer=16"; \
        echo "opcache.max_accelerated_files=10000"; \
        echo "opcache.revalidate_freq=5"; \
        echo "opcache.save_comments=1"; \
        echo "opcache.file_cache=${OPCACHE_FILE_CACHE_DIR}"; \
        echo "opcache.file_cache_only=0"; \
    } > /usr/local/etc/php/conf.d/opcache.ini \
    && echo "date.timezone=${TIMEZONE}" > /usr/local/etc/php/conf.d/timezone.ini

COPY nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p /run/nginx \
    && chown -R www-data:www-data "$APP_DIR" \
    && chmod -R 755 "$APP_DIR"

EXPOSE 80

CMD ["sh", "-c", "php-fpm -D && exec nginx -g 'daemon off;'"]
