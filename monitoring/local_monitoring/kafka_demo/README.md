# Recommendations consumption using Kafka 

With Kruize's local monitoring mode, let's explore a demonstration of consuming messages using Kafka in conjunction with the Bulk API. 

Kafka replaces the existing API workflow by adding the consumer mechanism which helps in an asynchronous communication between the client and Kruize.

User will start with a Bulk API request which returns a `job_id` as a response to track the job status. After that, internally Bulk API produces recommendations, and the same is being then sent via a Kafka Producer.
User can then consume it with the help of a consumer client as and when required. 

Refer the documentation of the [Kafka Design](https://github.com/kruize/autotune/blob/87b544c7e07deb22f683d6c124a0188f7b06d836/design/KafkaDesign.md) for details.(To be updated once the PR is merged)

## Demo workflow

- Start the bulk service
- Once completed, get the route of the kruize pod
- Setup kafka consumer client locally
- Get the TLS certificate from the server running the Kafka cluster
- Get the Kafka endpoint from the cluster
- Run the local kafka consumer using the certificate file generated to start Consuming the message from the recommendations-topic

To begin exploring the Kafka flow, follow these steps:

### Run the Demo

#### Pre-requisites

Kafka cluster needs to be running in an openshift cluster with a `route` listener added in it

##### Clone the demo repository:
```sh
git clone git@github.com:kruize/kruize-demos.git
```
##### Change directory to the local monitoring demo:
```sh
cd kruize-demos/monitoring/local_monitoring/kafka_demo
```
##### Execute the demo script in openshift as:
```sh
./kafka_demo.sh
```

```
 "Usage: ./kafka_demo.sh [-s|-t] [-i kruize-image] [-u datasource-url] [-d datasource-name]"
	 "s = start (default), t = terminate"
	 "i = Kruize image (default: $KRUIZE_IMAGE)"
	 "c = Cluster type (default: openshift)"
	exit 1
Note: All the params are optional and defaults are set in the script
Currently only openshift cluster is supported!
```
Example:
`./kafka_demo.sh -i quay.io/khansaad/autotune_operator:kafka `
