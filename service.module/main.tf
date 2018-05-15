variable "name" {}
variable "project" {}
variable "cluster_id" {}
variable "task_definition" {}
variable "desired_count" { default = "1" }
variable "deployment_maximum_percent" {default = "200"}
variable "deployment_minimum_healthy_percent" {default = "100"}
variable "container_name" {}
variable "create_alb" { default = false }
variable "container_port" { default = "80" }
variable "container_protocol" { default = "HTTP"}
variable "vpc_id" {}
variable "health_check_path" { default = "/" }
variable "certificate_arn" { default = "" }
variable "ecs_service_role_arn" {}
variable "mgmt_zone_id" {}
variable "mgmt_zone_name" {}
variable "recordname" {}
variable "region" {}
variable "task_role_arn" {}
variable "launch_type" {}
variable "namespace_id" {}
variable "container_sgs" {
  type = "list"
  default = [""]
}
variable "container_subnets" {
  type = "list"
  default = [""]
}

variable "alb_security_group_ids" {
  type = "list" 
  default = [""]
}

variable "alb_subnet_ids" {
  type = "list" 
  default = [""]
}

# AWS Private DNS RECORDS

resource "aws_service_discovery_service" "service" {
  name = "${var.container_name}"
  dns_config {
    namespace_id = "${var.namespace_id}"
    dns_records {
      ttl = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

    health_check_custom_config {
    failure_threshold = 1
  }

}


## With ALB
resource "aws_ecs_service" "web_service_alb" {
  count = "${var.create_alb ? 1 : 0 }"
  name            = "${var.name}"
  cluster         = "${var.cluster_id}"
  task_definition = "${data.aws_ecs_task_definition.task.family}:${max("${aws_ecs_task_definition.task.revision}", "${data.aws_ecs_task_definition.task.revision}")}"
  desired_count   = "${var.desired_count}"
  deployment_maximum_percent = "${var.deployment_maximum_percent}"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  launch_type     = "${var.launch_type}"
  #iam_role        = "${var.ecs_service_role_arn}"

  # placement_strategy {
  #   type  = "spread"
  #   field = "attribute:ecs.availability-zone"
  # }
  network_configuration {
    security_groups = ["${var.container_sgs}"]
    subnets = ["${var.container_subnets}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.main.id}"
    container_name   = "${var.container_name}"
    container_port   = "${var.container_port}"
  }

  lifecycle {
    #create_before_destroy = true
    ignore_changes = ["desired_count"]
  }

  service_registries {
    registry_arn = "${aws_service_discovery_service.service.arn}"
  }

  depends_on = [
  "aws_alb_listener.front_end",
  ]
}
resource "aws_cloudwatch_log_group" "main" {
  name = "${var.project}/${var.container_name}"
}

resource "aws_ecs_task_definition" "task" {
  family = "${var.task_definition}"
  network_mode = "awsvpc"
  requires_compatibilities  = ["FARGATE", "EC2"]
  execution_role_arn = "${var.task_role_arn}"
  cpu = "256"
  memory = "512"

  lifecycle {
      ignore_changes = ["container_definitions"]
  }

  container_definitions = <<DEFINITION
[
  {
    "cpu": 256,
    "environment": [{
      "name": "APACHE_HTTP_PORT_NUMBER",
      "value": "${var.container_port}"
    }],
    "portMappings": [
      {
        "containerPort": ${var.container_port}
      }
    ],
    "essential": true,
    "image": "bitnami/apache:latest",
    "memory": 512,
    "memoryReservation": 64,
    "name": "${var.task_definition}",
    "NetworkMode": "awsvpc",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.main.name}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "${var.region}"
        }
    }
    
  }
]
DEFINITION
}

data "aws_ecs_task_definition" "task" {
  task_definition = "${var.task_definition}" 
  depends_on = [ "aws_ecs_task_definition.task" ]
}

## Without ALB
resource "aws_ecs_service" "web_service" {
  count = "${var.create_alb ? 0 : 1 }"
  name            = "${var.name}"
  cluster         = "${var.cluster_id}"
  task_definition = "${data.aws_ecs_task_definition.task.family}:${max("${aws_ecs_task_definition.task.revision}", "${data.aws_ecs_task_definition.task.revision}")}"
  desired_count   = "${var.desired_count}"
  deployment_maximum_percent = "${var.deployment_maximum_percent}"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  iam_role        = "${var.ecs_service_role_arn}"
  launch_type     = "${var.launch_type}"
  network_configuration {
    security_groups = ["${var.container_sgs}"]
    subnets = ["${var.container_subnets}"]
  }
  placement_strategy {
    type  = "spread"
    field = "host"
  }
  lifecycle {
    create_before_destroy = true
  }
}

## ALB
resource "aws_alb_target_group" "main" {
  count = "${var.create_alb ? 1 : 0 }"
  name     = "${var.container_name}-${var.container_port}-ecs-tg"
  port     = "${var.container_port}"
  protocol = "${var.container_protocol}"
  vpc_id   = "${var.vpc_id}"
  deregistration_delay = 30
  target_type = "ip"


  health_check {
    path = "${var.health_check_path}"
    timeout = 10
    healthy_threshold = 2
    unhealthy_threshold = 10
    interval = 15
    matcher = "200-399"

  }

 # stickiness {
 #   type = "lb_cookie"
 #   cookie_duration = "600"
 # }
}

# resource "aws_route53_record" "main" {
#   zone_id = "${var.mgmt_zone_id}"
#   name    = "${var.recordname}.${var.mgmt_zone_name}"
#   type    = "A"

#   alias {
#     name                   = "${aws_alb.main.dns_name}"
#     zone_id                = "${aws_alb.main.zone_id}"
#     evaluate_target_health = true
#   }
# }

resource "aws_alb" "main" {
  count = "${var.create_alb ? 1 : 0 }"
  name            = "${var.container_name}-ecs-alb"
  subnets         = ["${var.alb_subnet_ids}"]
  security_groups = ["${concat(list(aws_security_group.lb_sg.id), var.alb_security_group_ids)}"]
}

resource "aws_alb_listener" "front_end_ssl" {
  count = "${var.create_alb ? (var.certificate_arn == "" ? 0 : 1) : 0 }"
  load_balancer_arn = "${aws_alb.main.0.id}"

  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2015-05"
  certificate_arn   = "${var.certificate_arn}"


  default_action {
    target_group_arn = "${aws_alb_target_group.main.0.id}"
    type             = "forward"
  }
}

## No SSL
resource "aws_alb_listener" "front_end" {
  count = "${var.create_alb ? 1 : 0 }"
  load_balancer_arn = "${aws_alb.main.0.id}"

  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.main.0.id}"
    type             = "forward"
  }
}

resource "aws_security_group" "lb_sg" {
  count         = "${var.create_alb ? 1 : 0 }"
  description   = "controls access to the application ELB"

  vpc_id        = "${var.vpc_id}"
  name_prefix   = "${var.container_name}-lb-ecs-sg"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }


  lifecycle {
    ignore_changes = ["ingress"]
  } 
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
    "0.0.0.0/0",
    ]
  }
  tags {
    Name = "${var.container_name}-ecs-lb-sg"
    "Terraform" = "true"
    "Environment" = "${var.container_name}"
  }
}

output "alb_securitygroup"  {  value = "${element(concat(aws_security_group.lb_sg.*.id, list("")), 0)}" }
output "targetgroup_arn"    {  value = "${element(concat(aws_alb_target_group.main.*.arn, list("")), 0)}" }
output "container_name"     {  value = "${var.container_name}"}
output "alb_name"           {  value = "${var.container_name}-ecs-alb"}
output "alb_arn"            {  value = "${element(concat(aws_alb.main.*.id, list("")), 0)}" }
output "alb_dns_name"       {  value = "${element(concat(aws_alb.main.*.dns_name, list("")), 0)}" }
output "alb_zone_id"        {  value = "${element(concat(aws_alb.main.*.zone_id, list("")), 0)}" }
output "log_group"          {  value = "${aws_cloudwatch_log_group.main.name}" }

# output "alb_securitygroup"  {  value = ""}
# output "targetgroup_arn"    {  value = ""}
# output "container_name"     {  value = "${var.container_name}"}
# output "alb_name"           {  value = "${var.container_name}-ecs-alb"}
# output "alb_arn"            {  value = ""}
# output "alb_dns_name"       {  value = ""}
# output "alb_zone_id"        {  value = ""}