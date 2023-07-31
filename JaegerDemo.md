# Jaeger Demo
This demo instruments a microservices springboot application using Jaeger to fetch the dependecies using Jaeger API.

## How do I run it?

```
./jaeger_demo_setup.sh
```

To view the dependecies Api response from Jaeger follow the given steps:

- Find the name of Kruize pod.
```
kubectl get pods -n monitoring
```

- To see the output of Kruize logs
```
kubectl logs <Name of kruize pod> -n monitoring
```
