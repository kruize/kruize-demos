# Autotune Demo Scripts

Scripts to Demonstrate Autotune Functionality

- [minikube demo](/minikube_demo.sh)
  It expects minikube to be installed with atleast 8 CPUs and 16384MB Memory. It does the following steps
  1. Clone autotune git repos
  2. Delete any existing minikube cluster (WARNING: Thats right, it deletes existing minikube !)
  3. Start new minikube cluster
  4. Install Prometheus and Grafana
  5. Install galaxies (quarkus REST CRUD) benchmark into cluster
  6. Install petclinic (springboot REST CRUD) benchmark into cluster
  7. Install Autotune
  8. Install Autotune Object for galaxies app
  9. Install Autotune Object for petclinic app
  10. [Optional] Port forward Prometheus
