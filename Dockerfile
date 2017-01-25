FROM jruby:9

RUN apt-get update \
    && apt-get install -y git

ENV MEDA_LOCATION /usr/src/app/meda_configs/meda.yml
ENV DATASET_LOCATION /usr/src/app/meda_configs/datasets.yml
ENV JRUBY_OPTS -J-Xmx1g

RUN mkdir -p /usr/src/app

WORKDIR /usr/src/app

COPY . /usr/src/app

VOLUME /usr/src/app/log
VOLUME /usr/src/app/meda_data
VOLUME /usr/src/app/meda_configs

RUN bundle install --without development && gem install puma

EXPOSE 8000

CMD puma --config /usr/src/app/config.rb