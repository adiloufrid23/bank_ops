# ═══════════════════════════════════════════════════════════════════════════
# Dockerfile — API REST Spring Boot (multi-stage build)
# ═══════════════════════════════════════════════════════════════════════════

# Stage 1 : Build
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
# RUN mvn clean package -DskipTests

# Stage 2 : Runtime
FROM eclipse-temurin:17-jre-alpine

LABEL maintainer="bankops-team"
LABEL description="API REST - Services bancaires"

RUN addgroup -S bankops && adduser -S bankops -G bankops
RUN mkdir -p /app/logs && chown -R bankops:bankops /app

WORKDIR /app
# COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080

USER bankops

HEALTHCHECK --interval=20s --timeout=5s --retries=3 --start-period=30s \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
