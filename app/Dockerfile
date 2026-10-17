# NOTE: pinned to version tags (not digests) — digest pinning is a nice-to-have
# but requires fetching real current digests from the registry, which needs
# to be done from an environment with Docker Hub access.

FROM node:20-alpine AS build
WORKDIR /build
COPY app/package*.json ./
RUN npm ci
COPY app/ .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /build/dist /usr/share/nginx/html
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
