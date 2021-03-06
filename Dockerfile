#
# Copyright (c) 2020, MariaDB Corporation. All rights reserved.
#
FROM centos:7
#
LABEL maintainer="MariaDB Corporation Ab"
#
ENV GOSU_VERSION=1.12
ARG ES_TOKEN
ARG ES_VERSION=10.5
ARG SETUP_SCRIPT=https://dlm.mariadb.com/enterprise-release-helpers/mariadb_es_repo_setup
#
RUN curl -L ${SETUP_SCRIPT} > /tmp/es_repo_setup && chmod +x /tmp/es_repo_setup && \
    /tmp/es_repo_setup  --token=${ES_TOKEN} --apply --verbose --skip-maxscale \
    --mariadb-server-version=${ES_VERSION} && rm -fv /tmp/es_repo_setup
#
RUN yum -y install MariaDB-server MariaDB-client MariaDB-backup && \
    yum clean all && rm -fv /etc/yum.repos.d/mariadb.repo && rm -fr /var/lib/mysql && \
    mkdir /var/lib/mysql && echo "ES_VERSION=${ES_VERSION}" >> /etc/IMAGEINFO
#
# add gosu for easy step-down from root
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && curl -o /usr/local/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64" \
    && curl -o /usr/local/bin/gosu.asc -SL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64.asc" \
    && gpg --verify /usr/local/bin/gosu.asc \
    && rm /usr/local/bin/gosu.asc \
    && rm -fr /root/.gnupg/ \
    && chmod +x /usr/local/bin/gosu
#
RUN mkdir /es-initdb.d
#
VOLUME /var/lib/mysql
COPY es-entrypoint.sh /es-entrypoint.sh
COPY zz_es-docker.cnf /etc/my.cnf.d/
ENTRYPOINT ["/es-entrypoint.sh"]
EXPOSE 3306/tcp
CMD ["mysqld"]
