# Jaeger Demo
This demo deploys kruize, jaeger and a microservices spring boot application that is instrumented using jaeger in minikube. Kruize then fetches the microservices dependencies using the Jaeger [API](https://www.jaegertracing.io/docs/1.23/apis/#service-dependencies-graph-internal). You can find the details about the microservices application used [here](https://github.com/kruize/jaeger-demos/blob/main/JaegerDependencyDemo.md).

## How do I run it?

```
./jaeger_demo_setup.sh
```

To view the dependencies API response from Jaeger follow the given steps:

- Find the name of Kruize pod.
```
kubectl get pods -n monitoring
```

- To see the output of Kruize logs
```
kubectl logs <Name of kruize pod> -n monitoring
```
