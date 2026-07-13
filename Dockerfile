FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=https://cobreja-backend-production.up.railway.app
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM node:22-alpine

WORKDIR /app

RUN npm install -g serve

COPY --from=build /app/build/web ./build/web

CMD sh -c "serve -s build/web -l ${PORT:-8080}"
