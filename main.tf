terraform {
  cloud {
    organization = "flink_ccloud_nks"

    workspaces {
      name = "cicd_flink_ccloud"
    }
  }

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.2.0"
    }
  }
}
locals {
  cloud  = "AWS"
  region = "us-east-2"
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Create a new environment.
resource "confluent_environment" "my_env" {
  display_name = "my_env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

# Create a new Kafka cluster.
resource "confluent_kafka_cluster" "my_kafka_cluster" {
  display_name = "my_kafka_cluster"
  availability = "SINGLE_ZONE"
  cloud        = local.cloud
  region       = local.region
  basic {}

  environment {
    id = confluent_environment.my_env.id
  }

  depends_on = [
    confluent_environment.my_env
  ]
}

# Access the Stream Governance Essentials package to the environment.
data "confluent_schema_registry_cluster" "my_sr_cluster" {
  environment {
    id = confluent_environment.my_env.id
  }
}

# Create a new Service Account. This will used during Kafka API key creation and Flink SQL statement submission.
resource "confluent_service_account" "my_service_account" {
  display_name = "my_service_account"
}

data "confluent_organization" "my_org" {}

# Assign the OrganizationAdmin role binding to the above Service Account.
# This will give the Service Account the necessary permissions to create topics, Flink statements, etc.
# In production, you may want to assign a less privileged role.
resource "confluent_role_binding" "my_org_admin_role_binding" {
  principal   = "User:${confluent_service_account.my_service_account.id}"
  role_name   = "OrganizationAdmin"
  crn_pattern = data.confluent_organization.my_org.resource_name

  depends_on = [
    confluent_service_account.my_service_account
  ]
}

# Create a Flink compute pool to execute a Flink SQL statement.
resource "confluent_flink_compute_pool" "my_compute_pool" {
  display_name = "my_compute_pool"
  cloud        = local.cloud
  region       = local.region
  max_cfu      = 10

  environment {
    id = confluent_environment.my_env.id
  }

  depends_on = [
    confluent_environment.my_env
  ]
}

# Create a Flink-specific API key that will be used to submit statements.
data "confluent_flink_region" "my_flink_region" {
  cloud  = local.cloud
  region = local.region
}

resource "confluent_api_key" "my_flink_api_key" {
  display_name = "my_flink_api_key"

  owner {
    id          = confluent_service_account.my_service_account.id
    api_version = confluent_service_account.my_service_account.api_version
    kind        = confluent_service_account.my_service_account.kind
  }

  managed_resource {
    id          = data.confluent_flink_region.my_flink_region.id
    api_version = data.confluent_flink_region.my_flink_region.api_version
    kind        = data.confluent_flink_region.my_flink_region.kind

    environment {
      id = confluent_environment.my_env.id
    }
  }

  depends_on = [
    confluent_environment.my_env,
    confluent_service_account.my_service_account
  ]
}

# Deploy a Flink SQL statement to Confluent Cloud.
resource "confluent_flink_statement" "my_flink_statement" {
  organization {
    id = data.confluent_organization.my_org.id
  }

  environment {
    id = confluent_environment.my_env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.my_compute_pool.id
  }

  principal {
    id = confluent_service_account.my_service_account.id
  }

  # This SQL reads data from source_topic, filters it, and ingests the filtered data into sink_topic.
  statement = <<EOT
    CREATE TABLE my_sink_topic_1 AS
    SELECT
      window_start,
      window_end,
      SUM(price) AS total_revenue,
      COUNT(*) AS cnt
    FROM
    TABLE(TUMBLE(TABLE `examples`.`marketplace`.`orders`, DESCRIPTOR($rowtime), INTERVAL '1' MINUTE))
    GROUP BY window_start, window_end;
    EOT

  properties = {
    "sql.current-catalog"  = confluent_environment.my_env.display_name
    "sql.current-database" = confluent_kafka_cluster.my_kafka_cluster.display_name
  }

  rest_endpoint = data.confluent_flink_region.my_flink_region.rest_endpoint

  credentials {
    key    = confluent_api_key.my_flink_api_key.id
    secret = confluent_api_key.my_flink_api_key.secret
  }

  depends_on = [
    confluent_api_key.my_flink_api_key,
    confluent_flink_compute_pool.my_compute_pool,
    confluent_kafka_cluster.my_kafka_cluster
  ]
}


