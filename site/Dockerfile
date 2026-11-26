# Образ сайта CodeLab: готовый статический dist/ (Astro) за nginx.
# dist/ собирается на хосте (npm run build с SITE_URL), образ только раздаёт файлы.
FROM nginx:1.28.0-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
EXPOSE 80
