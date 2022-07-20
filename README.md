# Example code to show how AppSync HTTP data source can read values from SSM parameter store and Secrets manager

## Deploy

* ```terraform init```
* ```terraform apply```

## Usage

Send a request to the AppSync API:

```graphql
query MyQuery {
  secret
  ssm_parameter
}
```

The result has the two values:

```json
{
  "data": {
    "secret": "secret value",
    "ssm_parameter": "secret"
  }
}
```

## Cleanup

* ```terraform destroy```
