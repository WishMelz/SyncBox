# Legacy standalone Web image. Production uses the single image in backend/Dockerfile.
FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json backend/package.json
COPY frontend/web/package.json frontend/web/package.json
RUN npm ci --workspace @syncbox/web --include-workspace-root=false
COPY frontend/web frontend/web
RUN npm run build -w @syncbox/web

FROM nginx:stable-alpine
COPY infra/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/frontend/web/dist /usr/share/nginx/html
EXPOSE 80
