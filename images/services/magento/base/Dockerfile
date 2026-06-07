FROM alpine AS unpack
WORKDIR /unpack
ARG COMPOSER_VER=2.10.1
ARG N98_MAGERUN2_VER=9.5.1
RUN wget https://getcomposer.org/download/${COMPOSER_VER}/composer.phar -O composer \
  && wget https://files.magerun.net/n98-magerun2-${N98_MAGERUN2_VER}.phar -O n98-magerun2

FROM php:8.5-fpm

# System dependencies (libraries needed by the PHP extensions below + dev tools)
RUN apt-get update \
  && apt-get install -y \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    libxslt1-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    libedit-dev \
    libsqlite3-dev \
    libargon2-dev \
    sudo \
    unzip \
    git \
    netcat-openbsd \
    vim \
    jq \
    procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# PHP extensions (configure gd with freetype + jpeg before building).
# Magento 2.4.x required/recommended set on PHP 8.5.
# `ftp` is a hard requirement of magento/product-community-edition and is NOT
# enabled by default in the official php:8.5-fpm image, so it must be built here.
# Not installed here, on purpose:
#   - curl / dom / simplexml / xmlwriter / sodium — enabled by default in the
#     official php:8.5-fpm image;
#   - opcache — statically built into PHP 8.5 (no shared module to build/enable),
#     turn it on via php.ini `opcache.enable=1` in the service layer.
# Installing any of the above breaks with "cp: cannot stat 'modules/*'".
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" \
    bcmath \
    exif \
    ftp \
    gd \
    intl \
    mbstring \
    pcntl \
    pdo_mysql \
    soap \
    sockets \
    xsl \
    zip

# phpredis client — Magento's Redis-protocol cache/session backends (Credis) use
# it when present for a significant speed-up. The stack runs Valkey (a Redis
# fork); phpredis speaks to it unchanged. The pre-seeded env.php wires the Valkey
# host for cache (db 0/1) and sessions (db 2).
RUN pecl install redis && docker-php-ext-enable redis

# Composer
ENV COMPOSER_ALLOW_SUPERUSER=1
VOLUME /root/.composer/cache
COPY --from=unpack /unpack/composer /usr/local/bin/composer
RUN chmod +x /usr/local/bin/composer

# netz98 magerun (Magento Swiss-army CLI: sys:info, db:*, cache:*, dev:* …)
COPY --from=unpack /unpack/n98-magerun2 /usr/local/bin/n98-magerun2
RUN chmod +x /usr/local/bin/n98-magerun2

# Xdebug (installed but not enabled — toggled at runtime via PHP_ENABLE_XDEBUG)
ARG XDEBUG_VER=3.5.1
RUN pecl install -o -f xdebug-${XDEBUG_VER}
ENV PHP_ENABLE_XDEBUG=false

# PHP SPX profiler (built from source, web UI exposed via SPX_KEY)
ARG SPX_VER=0.4.22
RUN cd /usr/lib && git clone --depth 1 --branch v${SPX_VER} https://github.com/NoiseByNorthwest/php-spx.git
RUN cd /usr/lib/php-spx && phpize && ./configure && make && make install
