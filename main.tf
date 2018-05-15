variable "service_env"      { }
variable "service_name"     { }
variable "project" {}
variable "certificate_arn"  { }
variable "container_instance_security_group_id" {}
variable "cluster_id" {}
variable "vpc_id" {}
variable "ecs_service_role_arn" {}
variable "mgmt_zone_id" {}
variable "mgmt_zone_name" {}
variable "alb_subnet_ids" { type = "list" }
variable "container_port" { default = "80" }
variable "region" {}
variable "task_role_arn" {}
variable "launch_type" {}
variable "namespace_id" {}

variable "container_subnets" {
  type = "list"
  default = [""]
}

module "service" {
  source = "./service.module"
  name = "${var.service_name}"
  project = "${var.project}"
  cluster_id = "${var.cluster_id}"
  task_definition = "${var.service_name}"
  container_name = "${var.service_name}"
  desired_count = "2"
  certificate_arn = "${var.certificate_arn}"
  create_alb = true
  vpc_id = "${var.vpc_id}"
  ecs_service_role_arn = "${var.ecs_service_role_arn}"
  mgmt_zone_id = "${var.mgmt_zone_id}"
  mgmt_zone_name ="${var.mgmt_zone_name}"
  recordname = "${var.service_env}"
  alb_subnet_ids = "${var.alb_subnet_ids}"
  container_port = "${var.container_port}"
  region = "${var.region}"
  container_sgs = ["${var.container_instance_security_group_id}"]
  container_subnets = ["${var.container_subnets}"]
  task_role_arn = "${var.task_role_arn}"
  launch_type     = "${var.launch_type}"
  namespace_id = "${var.namespace_id}"
}

resource "aws_security_group_rule" "allow_alb_in" {
  type                      = "ingress"
  from_port                 = 0
  to_port                   = 65535
  protocol                  = "tcp"
  source_security_group_id  = "${module.service.alb_securitygroup}"
  security_group_id         = "${var.container_instance_security_group_id}"
}


output "service_name" {
  value = "${var.service_name}"
}
output "aws_cloudwatch_log_group" {
  value = "${module.service.log_group}"
}
output "targetgroup_arn" {
  value = "${module.service.targetgroup_arn}"
}
output "alb_securitygroup" {
  value = "${module.service.alb_securitygroup}"
}
output "container_name" {
  value = "${module.service.container_name}"
}
output "alb_name" {
  value = "${module.service.alb_name}"
}
output "alb_arn" {
  value = "${module.service.alb_arn}"
}
output "alb_dns_name" {
  value = "${module.service.alb_dns_name}"
}
output "alb_zone_id" {
  value = "${module.service.alb_zone_id}"
}
output "certificate_arn" {
  value = "${var.certificate_arn}"
}