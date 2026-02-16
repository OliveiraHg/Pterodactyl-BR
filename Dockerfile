# Stage 0: Build Assets (Frontend)
FROM --platform=$TARGETOS/$TARGETARCH node:16-alpine AS builder
WORKDIR /app
COPY . ./
# Usando --network-timeout para evitar erros em conexões lentas no build do Render
RUN yarn install --frozen-lockfile --network-timeout 1000000 \
    && yarn run build:production

# Stage 1: Runtime (PHP + Nginx)
FROM --platform=$TARGETOS/$TARGETARCH php:8.3-fpm-alpine
WORKDIR /app

# Instalação de dependências do sistema
RUN apk add --no-cache --update \
    ca-certificates dcron curl git supervisor tar unzip nginx \
    libpng-dev libxml2-dev libzip-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install bcmath gd pdo_mysql zip

# Composer
COPY --from=composer:latest /usr/local/bin/composer /usr/local/bin/composer

# Copia os arquivos do projeto
COPY . ./
# Copia apenas os assets compilados do Stage 0
COPY --from=builder /app/public/assets ./public/assets

# Configuração de permissões e diretórios
RUN mkdir -p bootstrap/cache/ storage/logs storage/framework/sessions storage/framework/views storage/framework/cache \
    && chmod 777 -R bootstrap storage \
    && composer install --no-dev --optimize-autoloader \
    && chown -R nginx:nginx .

# Ajuste do Nginx para usar a variável PORT do Render
# Removemos a porta fixa 80 e colocamos um placeholder que o entrypoint substituirá
RUN sed -i 's/listen 80;/listen ${PORT};/g' /etc/nginx/http.d/default.conf || true

# Configurações de processo
COPY .github/docker/default.conf /etc/nginx/http.d/default.conf
COPY .github/docker/www.conf /usr/local/etc/php-fpm.conf
COPY .github/docker/supervisord.conf /etc/supervisord.conf

# Script de inicialização customizado para o Render
RUN echo '#!/bin/sh\n\
sed -i "s/listen 80;/listen ${PORT};/g" /etc/nginx/http.d/default.conf\n\
php artisan migrate --force\n\
exec supervisord -n -c /etc/supervisord.conf' > /app/render-entrypoint.sh \
    && chmod +x /app/render-entrypoint.sh

# O Render usa uma porta dinâmica, mas informamos a 80 como referência interna
EXPOSE 80

ENTRYPOINT [ "/bin/sh", "/app/render-entrypoint.sh" ]
