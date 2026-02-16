# Stage 0: Build Assets (Inalterado)
FROM node:16-alpine AS builder
WORKDIR /app
COPY . ./
RUN yarn install --frozen-lockfile --network-timeout 1000000 \
    && yarn run build:production

# Stage 1: Runtime
FROM php:8.3-fpm-alpine
WORKDIR /app

# Instalação de dependências e ferramentas necessárias
RUN apk add --no-cache --update \
    ca-certificates dcron curl git supervisor tar unzip nginx \
    libpng-dev libxml2-dev libzip-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install bcmath gd pdo_mysql zip

# --- CORREÇÃO AQUI: Instalando Composer via CURL em vez de COPY ---
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copia os arquivos do projeto
COPY . ./
COPY --from=builder /app/public/assets ./public/assets

# Configuração de permissões
RUN mkdir -p bootstrap/cache/ storage/logs storage/framework/sessions storage/framework/views storage/framework/cache \
    && chmod 777 -R bootstrap storage \
    && composer install --no-dev --optimize-autoloader \
    && chown -R nginx:nginx .

# Ajuste de Porta para o Render
RUN sed -i 's/listen 80;/listen ${PORT};/g' /etc/nginx/http.d/default.conf || true

COPY .github/docker/default.conf /etc/nginx/http.d/default.conf
COPY .github/docker/www.conf /usr/local/etc/php-fpm.conf
COPY .github/docker/supervisord.conf /etc/supervisord.conf

# Script de Inicialização
RUN echo '#!/bin/sh\n\
sed -i "s/listen 80;/listen ${PORT};/g" /etc/nginx/http.d/default.conf\n\
php artisan migrate --force\n\
exec supervisord -n -c /etc/supervisord.conf' > /app/render-entrypoint.sh \
    && chmod +x /app/render-entrypoint.sh

EXPOSE 80
ENTRYPOINT [ "/bin/sh", "/app/render-entrypoint.sh" ]
