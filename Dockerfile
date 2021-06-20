#Use Ruby 3 Alpine image as base
FROM ruby:3.0.1-alpine3.13

#Run the Conatiner as non-root user 
USER nobody

#Set working directory for the application
WORKDIR /app

#Copy source code
COPY http_server.rb /app

#App listening port 
EXPOSE 80

#Run web app
CMD ["ruby", "http_server.rb"]
