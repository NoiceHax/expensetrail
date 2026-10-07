# ---- stage 1: build the static site with Node ----
FROM node:22-alpine AS build
WORKDIR /src
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY . .
RUN npm run build

# ---- stage 2: serve it with unprivileged nginx (no Node in the final image) ----
FROM nginxinc/nginx-unprivileged:1.27-alpine

# pick up OS security patches released after the base image was built, then drop back to the unprivileged user
USER root
RUN apk upgrade --no-cache
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080
