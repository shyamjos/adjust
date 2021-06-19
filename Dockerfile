FROM ruby:3.0.1-alpine3.13
USER nobody
WORKDIR /app
COPY http_server.rb /app
EXPOSE 80
CMD ["ruby", "http_server.rb"]
