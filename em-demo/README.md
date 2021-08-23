# EM DEMO

This directory consists of scripts required to run the Experiment Manager Demo

### Steps to be followed:

```
./em-start.sh
```

At the end of the output of the script you will be getting Autotune URL which you need to pass as an input for the next script as follows

```
./em-demo-script.sh <AUTOTUNE URL:PORT>
```

Now in another terminal you can have these command running to see the changes made by EM to the deployment

```
kubectl get deployment petclinic-sample -o yaml
```

To see the container getting recreated with given config you can have a tab opened with

```
watch kubectl get pods
```