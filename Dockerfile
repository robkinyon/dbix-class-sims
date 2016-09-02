# This is used for running the tests in a clean container.
# I use it as so:
#  * docker run --rm -v $(pwd):/app sims -lrs t

FROM perl:5.20
MAINTAINER rob.kinyon@gmail.com

RUN apt-get update -qq \
  && apt-get install -y build-essential unzip uuid-dev

RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm Module::Install

RUN mkdir -p /tmp/lib/DBIx/Class && mkdir -p /tmp/t
COPY Makefile.PL /tmp/
COPY lib/DBIx/Class/Sims.pm /tmp/lib/DBIx/Class
WORKDIR /tmp
RUN perl Makefile.PL && make install
RUN cpanm DBIx::Class::TopoSort

ENV app /app
RUN mkdir -p $app
WORKDIR $app

ENTRYPOINT [ "/usr/local/bin/prove" ]
