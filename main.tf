provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_ssm_parameter" "value" {
  name  = "parameter_${random_id.id.hex}"
  type  = "String"
  value = "secret"
}

resource "aws_secretsmanager_secret" "secret" {
  name = "secret_${random_id.id.hex}"
}

resource "aws_secretsmanager_secret_version" "secret" {
  secret_id     = aws_secretsmanager_secret.secret.id
  secret_string = "secret value"
}

resource "aws_iam_role" "appsync" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "appsync" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
			aws_ssm_parameter.value.arn
    ]
  }
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
			aws_secretsmanager_secret_version.secret.arn
    ]
  }
}

resource "aws_iam_role_policy" "appsync_logs" {
  role   = aws_iam_role.appsync.id
  policy = data.aws_iam_policy_document.appsync.json
}

resource "aws_appsync_graphql_api" "appsync" {
  name                = "appsync_test"
  schema              = file("schema.graphql")
  authentication_type = "AWS_IAM"
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync.arn
    field_log_level          = "ALL"
  }
}

resource "aws_cloudwatch_log_group" "loggroup" {
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.appsync.id}"
  retention_in_days = 14
}

data "aws_arn" "ssm_parameter" {
  arn = aws_ssm_parameter.value.arn
}

data "aws_arn" "secret" {
  arn = aws_secretsmanager_secret_version.secret.arn
}

resource "aws_appsync_datasource" "parameter_store" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "ssm"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "HTTP"
	http_config {
		endpoint = "https://ssm.${data.aws_arn.ssm_parameter.region}.amazonaws.com"
		authorization_config {
			authorization_type = "AWS_IAM"
			aws_iam_config {
				signing_region = data.aws_arn.ssm_parameter.region
				signing_service_name = "ssm"
			}
		}
	}
}

resource "aws_appsync_datasource" "secret" {
  api_id           = aws_appsync_graphql_api.appsync.id
  name             = "secret"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "HTTP"
	http_config {
		endpoint = "https://secretsmanager.${data.aws_arn.secret.region}.amazonaws.com"
		authorization_config {
			authorization_type = "AWS_IAM"
			aws_iam_config {
				signing_region = data.aws_arn.secret.region
				signing_service_name = "secretsmanager"
			}
		}
	}
}

# resolvers
resource "aws_appsync_resolver" "Query_ssm_parameter" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "ssm_parameter"
  data_source = aws_appsync_datasource.parameter_store.name
	request_template = <<EOF
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"headers": {
			"Content-Type" : "application/x-amz-json-1.1",
			"X-Amz-Target" : "AmazonSSM.GetParameter"
		},
		"body": {
			"Name": "${aws_ssm_parameter.value.name}",
			"WithDecryption": true
		}
	},
	"resourcePath": "/"
}
EOF

	response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
$util.toJson($util.parseJson($ctx.result.body).Parameter.Value)
EOF
}

resource "aws_appsync_resolver" "Query_secret" {
  api_id      = aws_appsync_graphql_api.appsync.id
  type        = "Query"
  field       = "secret"
  data_source = aws_appsync_datasource.secret.name
	request_template = <<EOF
{
	"version": "2018-05-29",
	"method": "POST",
	"params": {
		"headers": {
			"Content-Type" : "application/x-amz-json-1.1",
			"X-Amz-Target" : "secretsmanager.GetSecretValue"
		},
		"body": {
			"SecretId": "${aws_secretsmanager_secret.secret.id}"
		}
	},
	"resourcePath": "/"
}
EOF

	response_template = <<EOF
#if ($ctx.error)
	$util.error($ctx.error.message, $ctx.error.type)
#end
#if ($ctx.result.statusCode < 200 || $ctx.result.statusCode >= 300)
	$util.error($ctx.result.body, "StatusCode$ctx.result.statusCode")
#end
$util.toJson($util.parseJson($ctx.result.body).SecretString)
EOF
}

