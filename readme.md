# Readme

This repository contains instructions for deploying a simple ruby web app to a kubernetes cluster with high availability and load balancing.

# Ruby - Web APP (sawasy/http_server)

The sample ruby web app provided for the task was not giving proper http response message (was missing status-line and header section in the response) and because of this Kubernetes's readinessProbe was failing with below error message. 
```
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Warning  Unhealthy  0s (x8 over 34s)  kubelet            Readiness probe failed: Get "http://172.17.0.4:80/healthcheck": net/http: HTTP/1.x transport connection broken: malformed HTTP response "OK"
```
So I have modified the code and added status-line and header section to the response part.

```
require 'socket'

server  = TCPServer.new('0.0.0.0', 80)

loop {
  client  = server.accept
  request = client.readpartial(2048)
  
  method, path, version = request.lines[0].split

  puts "#{method} #{path} #{version}"

  if path == "/healthcheck"
    client.write "HTTP/1.1 200\r\n" 
    client.write "Content-Type: text/html\r\n"
    client.write "\r\n"
    client.write("OK\r\n")
  else
    client.write "HTTP/1.1 200\r\n" 
    client.write "Content-Type: text/html\r\n"
    client.write "\r\n"
    client.write("Well, hello there!\r\n")
  end

  client.close
}
```
After making this change kubernetes probes were successful 

## Dockerfile Explained

```
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
```

* Used official ruby alpine image to make the container lite and small
* Added `USER nobody` line to the dockerfile to run the container as a non-root user
* Added `.dockeringore` file to repository to exclude files and directories

## Setup Minikube

Follow [this guide](https://minikube.sigs.k8s.io/docs/start/) for installing minikube.
Once installed, we need to configure following add-ons

* ingress - In-order to create a ingress object we need an ingress controller
* metrics-server - To configure HPA we need a metrics provider 

```
minikube addons enable ingress
minikube addons enable metrics-server
```

## Achieving high availability in kubernetes

* Deployment Strategy: To avoid interruptions during deployments we are using a rolling update strategy with maxSurge: 5 and unavailable: 0
* podAntiAffinity: For better availability we are using podAntiAffinity to spread the pod among different nodes
* Limits: Proper limits and requests are configured after doing some load testing. For high traffic APIs CPU limits may cause [latency issues](https://github.com/kubernetes/kubernetes/issues/51135)
* readinessProbe: Since we are using readinessProbe containers wont receive live traffic until readinessProbe is successful, In most cases [you only need readinessProbe](https://srcco.de/posts/kubernetes-liveness-probes-are-dangerous.html)
* HorizontalPodAutoscaler: Here we are using the HorizontalPodAutoscaler object to scale the application based on CPU/Memory utilization
* PodDisruptionBudget: We are using PodDisruptionBudget to protect our application from voluntary evictions

## Deployment 

To deploy the application run below command 
```
kubectl apply -f ruby-app-k8s.yaml
```
To check if last deployment was successful run below command 
```
kubectl rollout status deployment adjust-ruby-app
```
To access the service run below command

```
curl -H "Host: ruby-app.adjust.local" http://$(minikube ip)
```

## Setup Github Actions / CD Pipeline
We are using following github action workflow to build and deploy application to a minikube cluster on every commit/PR.
See Github Actions tab for [more info](https://github.com/shyamjos/adjust/actions/workflows/pr.yml) 

```
name: "CI/CD Pipeline"
on:
  push:
    branches:
      - master
    paths-ignore:
      - '**.md'
  pull_request:
    paths-ignore:
      - '**.md'
jobs:
  CICD-minikube:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@master
    - uses: opsgang/ga-setup-minikube@v0.1.2
      with:
        minikube-version: 1.21.0
        k8s-version: 1.20.7
    - name: Setup Cluster
      run: |
        minikube config set vm-driver docker
        minikube config set kubernetes-version v1.20.7
        minikube start
        minikube update-context
        kubectl cluster-info
        kubectl get pods -A
    - name: Build image 
      run: | 
        export SHELL=/bin/bash
        eval $(minikube -p minikube docker-env)
        docker build -f ./Dockerfile -t adjust-ruby-app:latest .
        echo -n "verifying images:"
        docker images
    - name: Deploy to minikube
      run: 
        kubectl apply -f ruby-app-k8s.yaml && kubectl rollout status deployment adjust-ruby-app
```        

## Final Notes 
* As a next step we can create helm chart for easy customization and maintainbilty
* Configure network policy to limit access to the web app pods
