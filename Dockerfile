FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=https://cobreja-backend-production-0eda.up.railway.app
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM node:22-alpine

WORKDIR /app

RUN npm install -g serve

COPY --from=build /app/build/web ./build/web

EXPOSE 8080

CMD sh -c "APP_PORT=${PORT:-8080}; serve -s build/web -l tcp://0.0.0.0:${APP_PORT}"
