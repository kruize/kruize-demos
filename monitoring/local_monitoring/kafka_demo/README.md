# Recommendations consumption using Kafka 

With Kruize's local monitoring mode, let's explore a demonstration of consuming messages using Kafka in conjunction with the Bulk API. 

Kafka replaces the existing API workflow by adding the consumer mechanism which helps in an asynchronous communication between the client and Kruize.

User will start with a Bulk API request which returns a `job_id` as a response to track the job status. After that, internally Bulk API produces recommendations, and the same is being then sent via a Kafka Producer.
User can then consume it with the help of a consumer client as and when required. 

Refer the documentation of the [Kafka Design](https://github.com/kruize/autotune/blob/87b544c7e07deb22f683d6c124a0188f7b06d836/design/KafkaDesign.md) for details.(To be updated once the PR is merged)

## Demo workflow

- Install the Kafka server
- Get the bootstrap server URL and the required certificate details
- Update manifest files with the Kafka specific changes
- Initiate the bulk service and wait for it to finish
- Setup kafka consumer client locally
- Run the local kafka consumer using the bootstrap server and the certificate file generated to start Consuming the message from the recommendations-topic

To begin exploring the Kafka flow, follow these steps:

### Run the Demo

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
./kafka_demo.sh -b -k
```

```
 "Usage: $0 [-s|-t] [-b] [-k] [-i kruize-image] [-c cluster-name] [-n kafka-namespace] [-a kruize-namespace]"
	"s = start (default), t = terminate"
	"b = start bulk_demo"
	"k = start kafka_server_setup"
	"i = Kruize image (default: $KRUIZE_DOCKER_IMAGE)"
	"a = Kruize Namespace  (default: openshift-tuning)"
	"n = Kafka Namespace  (default: kafka)"
	"c = Cluster type (default: openshift)"

Note: All the params are optional and defaults are set in the script.

Note: When starting for the first time, pass the params `-b` and `k` to start the bulk service and the Kafka server setup respectively

Currently only openshift cluster is supported!
```
Example:
`./kafka_demo.sh -b -k -i quay.io/kruize/autotune_operator:0.5 `
