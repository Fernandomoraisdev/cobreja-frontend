FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=https://cobreja-backend-production-0eda.up.railway.app
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM node:22-alpine

WORKDIR /app

COPY --from=build /app/build/web ./build/web
COPY server.js ./server.js

EXPOSE 8080

CMD ["node", "server.js"]
