provider "aws" {
  region = "ca-central-1"
}

resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = "DynamoDB-Terraform"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "UserId"
  range_key      = "Name"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "Name"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  global_secondary_index {
    name               = "UserTitleIndex"
    hash_key           = "UserId"
    range_key          = "Name"
    write_capacity     = 10
    read_capacity      = 10
    projection_type    = "KEYS_ONLY" # Corrected projection_type
    non_key_attributes = []
  }

  tags = {
    Name        = "dynamodb-table"
    Environment = "Training"
  }
}

module "test_database" {
  source = "github.com/cds-snc/terraform-modules//rds?ref=50c0f631d2c8558e6eec44138ffc2e963a1dfa9a" # v9.6.0
  name   = "test-database"

  database_name           = "test"
  engine                  = "aurora-postgresql"
  engine_version          = "16.2"
  instances               = 1 # TODO: increase for prod loads
  instance_class          = "db.serverless"
  serverless_min_capacity = "1"
  serverless_max_capacity = "2"
  use_proxy               = false # TODO: enable for prod loads if performance requires it

  username = "wmadmin"
  password = "password"

  backup_retention_period      = 14
  preferred_backup_window      = "02:00-04:00"
  performance_insights_enabled = false

  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.security_group_idp_db_id]

  billing_tag_key   = "billing-tag-key"
  billing_tag_value = "billing-tag-value"
}

resource "aws_s3_bucket" "spill_bucket" {
  bucket = "wm-athena-spill-bucket"
}

/*
Enables Amazon Athena to communicate with DynamoDB, making your tables accessible via SQL
*/
resource "aws_serverlessapplicationrepository_cloudformation_stack" "dynamodb_connector" {
  name           = "dynamodb-connector"
  application_id = "arn:aws:serverlessrepo:us-east-1:292517598671:applications/AthenaDynamoDBConnector"
  capabilities = [
    "CAPABILITY_IAM",
    "CAPABILITY_RESOURCE_POLICY",
  ]
  parameters = {
    AthenaCatalogName = "dynamodb-lambda-connector"
    SpillBucket       = aws_s3_bucket.spill_bucket.id
  }
}

data "aws_lambda_function" "existing" {
  function_name = "dynamodb-lambda-connector"
  depends_on    = [aws_serverlessapplicationrepository_cloudformation_stack.dynamodb_connector]
}

resource "aws_athena_data_catalog" "dynamodb_data_catalog" {
  name        = "dynamodb-data-catalog"
  description = "Example Athena dynamodb data catalog"
  type        = "LAMBDA"

  parameters = {
    "function" = data.aws_lambda_function.existing.arn
  }
}



