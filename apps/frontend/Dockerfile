FROM node:20.14-alpine AS build

WORKDIR /app
COPY package.json /app/package.json
RUN npm install
COPY index.html vite.config.js /app/
COPY src /app/src
RUN npm run build

FROM nginx:1.26.2-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
