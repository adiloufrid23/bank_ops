# ═══════════════════════════════════════════════════════════════════════════
# Dockerfile — WebSphere Liberty Profile
# Image optimisée pour application bancaire Java EE
# ═══════════════════════════════════════════════════════════════════════════

FROM icr.io/appcafe/websphere-liberty:24.0.0.3-kernel-java17-openj9-ubi

# Métadonnées
LABEL maintainer="bankops-team"
LABEL description="WebSphere Liberty - Application bancaire"
LABEL version="1.0"

# Installer les features nécessaires
RUN features.sh javaee-10.0 microProfile-6.0 monitor-1.0 \
    transportSecurity-1.0 appSecurity-5.0 jdbc-4.3 jndi-1.0

# Copier la configuration serveur
COPY --chown=1001:0 server.xml /opt/ibm/wlp/usr/servers/defaultServer/server.xml

# Copier le driver JDBC PostgreSQL
ADD --chown=1001:0 https://jdbc.postgresql.org/download/postgresql-42.7.2.jar \
    /opt/ibm/wlp/usr/shared/resources/postgresql.jar

# Copier l'application (WAR)
# COPY --chown=1001:0 target/bankops.war /opt/ibm/wlp/usr/servers/defaultServer/apps/

# Créer les répertoires nécessaires
RUN mkdir -p /opt/ibm/wlp/output/defaultServer/logs && \
    chown -R 1001:0 /opt/ibm/wlp/output

# Port applicatif
EXPOSE 9080 9443

# Health check intégré
HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=60s \
    CMD curl -f http://localhost:9080/health || exit 1

# Utilisateur non-root
USER 1001
