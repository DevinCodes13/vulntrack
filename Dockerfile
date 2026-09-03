FROM quay.io/wildfly/wildfly:31.0.1.Final-jdk17

COPY modules/org/postgresql/main /opt/jboss/wildfly/modules/org/postgresql/main
COPY datasource.cli /opt/jboss/wildfly/datasource.cli

RUN /opt/jboss/wildfly/bin/jboss-cli.sh --file=/opt/jboss/wildfly/datasource.cli