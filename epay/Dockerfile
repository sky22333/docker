FROM php:8.1-apache

# 源码来源
ARG REPO_URL=https://github.com/maajiko/Epay.git

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libzip-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd pdo_mysql \
    && a2enmod rewrite deflate \
    && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /var/www/html

RUN git clone --depth=1 ${REPO_URL} /var/www/html \
    && chown -R www-data:www-data /var/www/html

EXPOSE 80

CMD ["apache2-foreground"]
