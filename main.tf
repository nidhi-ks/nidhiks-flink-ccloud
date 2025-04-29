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
