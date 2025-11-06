provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Project = "judi-pricing-demo"
    }
  }
  # shared_credentials_files = ["%USERPROFILE%/.aws/credentials"]
  ## Below is only for live demo not on my machine
  access_key = "AKIAZH7ISTLXURLCGRHF"
  secret_key = "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"
}

resource "aws_iam_role" "pricing_demo" {
  # TODO: implement role (DONE)
  name = "pricing_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}
# TODO: Get a better understand on how this works with the iam role
resource "aws_iam_role_policy_attachment" "pricing_demo_eni_attachment" {
  role       = aws_iam_role.pricing_demo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_vpc" "pricing_demo" {
  cidr_block           = "172.16.0.0/18"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "pricing_demo" {
  vpc_id            = aws_vpc.pricing_demo.id
  cidr_block        = cidrsubnet(aws_vpc.pricing_demo.cidr_block, 8, 0)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${data.aws_availability_zones.available.names[0]}_pricing_demo"
  }
}

resource "aws_route_table" "pricing_demo" {
  # TODO: implement route table (partial done maybe....I am not sure)
  vpc_id = aws_vpc.pricing_demo.id

  route {
    cidr_block = aws_vpc.pricing_demo.cidr_block
    gateway_id = "local"
  }
  #public internet traffic
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pricing_demo.id
  }
}

resource "aws_route_table_association" "pricing_demo" {
  depends_on = [aws_subnet.pricing_demo]

  subnet_id      = aws_subnet.pricing_demo.id
  route_table_id = aws_route_table.pricing_demo.id
}

resource "aws_security_group" "pricing_demo" {
  name        = "pricing_demo"
  description = "pricing_demo"
  vpc_id      = aws_vpc.pricing_demo.id

  # TODO: implement appropriate ingress and egress rules (DONE)
  # implementing in seperate resource per terraform documentation, 
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
  # Planned rules: only allows https inboud, allow all outbound
}

# Allow Https ipv4
resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.pricing_demo.id
  cidr_ipv4         = aws_vpc.pricing_demo.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
# Allow all outbound traffic ipv4
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.pricing_demo.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Zip the python code
data "archive_file" "pricing_demo_zip" {
  type        = "zip"
  source_file = "${path.module}/pricing.py"
  output_path = "${path.module}/pricing.zip"
}

resource "aws_lambda_function" "pricing_demo" {
  # TODO: implement function
  filename      = data.archive_file.pricing_demo_zip.output_path
  function_name = "pricing_demo_function"
  role          = aws_iam_role.pricing_demo.arn
  handler       = "pricing.handler"
  runtime       = "python3.13"
  memory_size   = 1024
  timeout       = 30

  vpc_config {
    subnet_ids         = [aws_subnet.pricing_demo.id]
    security_group_ids = [aws_security_group.pricing_demo.id]
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }
}

# TODO: implement function url (Partial complete)
resource "aws_lambda_function_url" "pricing_demo" {
  function_name      = aws_lambda_function.pricing_demo.function_name
  authorization_type = "NONE" # keeping in comment in case this is easier for testing
  # authorization_type = "AWS_IAM"
}
output "aws_lambda_function_url" {
  description = "The URL for the pricing lmbda"
  value       = aws_lambda_function_url.pricing_demo.function_url
}

resource "aws_cloudwatch_log_group" "pricing_demo" {
  # TODO: ensure the logs created by the log group do not expire (DONE)
  name              = "/aws/lambda/${aws_lambda_function.pricing_demo.function_name}"
  retention_in_days = 0
}

# TODO: implement an alarm that fires any time the pricing lambda function experiences an error (DONE)
resource "aws_cloudwatch_metric_alarm" "pricing_demo" {
  alarm_name          = "pricing-lambda-error"
  alarm_description   = "This metric monitors any errors in the pricing lambda."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.email_notification.arn]
  ok_actions          = [aws_sns_topic.email_notification.arn]

  metric_query {
    id          = "ep1"
    expression  = <<-EOT
      SELECT
        SUM(Errors)
      FROM SCHEMA("AWS/Lambda", FunctionName)
      WHERE FunctionName = '${aws_lambda_function.pricing_demo.function_name}'
    EOT
    period      = 60
    return_data = true
    label       = "Errors on pricing demo lambda"
  }
}

resource "aws_sns_topic" "email_notification" {
  name = "email-notification-topic"
}

resource "aws_sns_topic_subscription" "email_chad" {
  topic_arn = aws_sns_topic.email_notification.arn
  protocol  = "email"
  endpoint  = "chadn87@gmail.com"
}

## Extra stuff I added
# Resource group to easily see all resources
resource "aws_resourcegroups_group" "judi_pricing_demo" {
  name = "judi-pricing-demo-group"

  resource_query {
    query = <<JSON
    {
      "ResourceTypeFilters": [
        "AWS::AllSupported"
      ],
      "TagFilters": [
        {
          "Key": "Project",
          "Values": ["judi-pricing-demo"]
        }
      ]
    }
    JSON
  }
}