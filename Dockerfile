# Usamos apenas o PHP agora, pulando o estágio do Node/Yarn
FROM php:8.3-fpm-alpine
WORKDIR /app

# Dependências do Sistema
RUN apk add --no-cache --update \
    ca-certificates dcron curl git supervisor tar unzip nginx \
    libpng-dev libxml2-dev libzip-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install bcmath gd pdo_mysql zip

# Instalação do Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copia TODOS os arquivos (incluindo a pasta public/assets que você buildou localmente)
COPY . ./

# Configuração de permissões e dependências PHP
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
