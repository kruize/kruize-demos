## What is Kruize HPOaaS?

Machine learning is a process of teaching a system to make accurate predictions based on the data fed. Hyperparamter optimization (/ tuning) helps to choose the right set of parameters for a learning algorithm. HPO uses different methods like Manual, Random search, Grid search, Bayesian optimization. [Kruize HPOaaS](https://github.com/kruize/hpo/blob/master/README.md) currently uses Bayesian optimization because of the multiple advantages that it provides.

### [HPOaaS demo](/hpo_demo_setup.sh)

#### Goal
  The user has an objective function that needs to be either maximized or minimized. They also have a search space (aka Domain space) which consists of a group of hyperparameters and the range within which they operate. The user provides the objective function and the search space to HPOaaS (running natively or on minikube). HPOaaS then provides trial configs which the user can test (Eg with a benchmark) and then return the result back to HPOaaS. This is then done in a loop until the entire gets a satisfactory result with the objective function.
#### Steps
  This demo starts HPOaaS natively and then starts the TFB benchmark on minikube. It then starts an experiment with the given search space [JSON](/hpo_helpers/tfb_qrh_search_space.json) and runs it for 3 trials.
#### What does it do?
  Currently it provides a log that consists the results of all the trials and needs to be manually evaluated to see which configuration provided the best result.
#### pre-req
  It expects minikube to be installed with atleast 8 CPUs and 16384MB Memory.
#### Customize it for your usecase
   Follow [Customize the script for your usecase](hpo_helpers/README.md) to customize the demo script for your usecase.
##### WARNING: The script deletes any existing minikube cluster.
