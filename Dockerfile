FROM ubuntu:14.04
MAINTAINER Nikolay Ryzhikov <niquola@gmail.com>, Mike Lapshin <mikhail.a.lapshin@gmail.com>

RUN apt-get -qq update
RUN apt-get -qqy install git build-essential gettext libreadline6 libreadline6-dev zlib1g-dev flex bison libxml2-dev libxslt-dev || echo 'Ups. No sudo'
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

RUN locale-gen

RUN useradd -m -s /bin/bash dba
RUN echo "dba:qwerty"|chpasswd
RUN adduser dba sudo

USER dba
ENV BUILD_DIR /home/dba

ENV PGDATA /home/dba/data
ENV PGPORT 5777
ENV PGHOST localhost
ENV SOURCE_DIR /home/dba/src
ENV PG_BIN /home/dba/bin
ENV PG_CONFIG /home/dba

USER dba

RUN echo $LC_ALL
RUN locale

# install postgresql
RUN git clone -b REL9_4_STABLE --depth=1 git://git.postgresql.org/git/postgresql.git  $SOURCE_DIR	
RUN XML2_CONFIG=`which xml2-config` cd $SOURCE_DIR && ./configure --prefix=$BUILD_DIR --with-libxml && make && make install

# install jsquery
RUN git clone https://github.com/akorotkov/jsquery.git $SOURCE_DIR/contrib/jsquery
ENV JSQUERY_V bfa87d1df0e2417a92c3ed204ebf4aa63e3b0d9c

USER dba
RUN cd $SOURCE_DIR/contrib/jsquery && git checkout $JSQUERY_V && make && make install

RUN mkdir $PGDATA
RUN ls -lah $PG_BIN
RUN $PG_BIN/initdb -D $PGDATA -E utf8
RUN echo "host all  all    0.0.0.0/0  md5" >> $PGDATA/pg_hba.conf && echo "listen_addresses='*'\nport=$PGPORT" >> $PGDATA/postgresql.conf

# Expose the PostgreSQL port
EXPOSE 5777
CMD ["$PG_BIN/pg_ctl", "-D", "$PGDATA", "start"]
