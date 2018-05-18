variable "stage" {}
variable "namespace" {}

variable "attributes" {
  type    = "list"
  default = []
}

variable "name" {}
variable "certificate_arn" {}

variable "security_group_ids" {
  type = "list"
}

variable "cluster_id" {}
variable "vpc_id" {}
variable "ecs_service_role_arn" {}
variable "service_zone_id" {}
variable "service_zone_name" {}

variable "network_mode" {
  default = "awsvpc"
}

variable "requires_compatibilities" {
  default = ["FARGATE", "EC2"]
}

variable "alb_subnet_ids" {
  type = "list"
}

variable "alb_listen_port" {
  default = "80"
}

variable "container_port" {
  default = "80"
}

variable "container_protocol" {
  default = "HTTP"
}

variable "health_check_path" {
  default = "/"
}

variable "container_cpu" {
  default = "256"
}

variable "container_memory" {
  default = "512"
}

variable "container_memoryreservation" {
  default = "64"
}

variable "container_image" {
  default = "bitnami/apache:latest"
}

variable "deployment_maximum_percent" {
  default = "200"
}

variable "deployment_minimum_healthy_percent" {
  default = "100"
}

variable "log_retention_in_days" {
  default = "365"
}

variable "deregistration_delay" {
  default = "15"
}

variable "tags" {
  default = {}
}

variable "region" {
  default = "us-east-1"
}

#variable "task_role_arn" {}

variable "launch_type" {
  default = "FARGATE"
}

variable "service_discovery_namespace_id" {
  default = "NONE"
}

variable "desired_count" {
  default = "2"
}

variable "container_subnets" {
  type    = "list"
  default = [""]
}

module "service_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.5"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "service"
  tags      = "${merge(map("ManagedBy", "Terraform"), var.tags)}"
}

module "task_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.5"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "task"
  tags      = "${merge(map("ManagedBy", "Terraform"), var.tags)}"
}

## With ALB
resource "aws_ecs_service" "default" {
  name                               = "${module.service_label.id}"
  cluster                            = "${var.cluster_id}"
  task_definition                    = "${data.aws_ecs_task_definition.task.family}:${max("${aws_ecs_task_definition.task.revision}", "${data.aws_ecs_task_definition.task.revision}")}"
  desired_count                      = "${var.desired_count}"
  deployment_maximum_percent         = "${var.deployment_maximum_percent}"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  launch_type                        = "${var.launch_type}"

  #iam_role        = "${var.ecs_service_role_arn}"

  # placement_strategy {
  #   type  = "spread"
  #   field = "attribute:ecs.availability-zone"
  # }
  network_configuration {
    security_groups = ["${var.security_group_ids}"]
    subnets         = ["${var.container_subnets}"]
  }
  load_balancer {
    target_group_arn = "${aws_alb_target_group.main.id}"
    container_name   = "${module.task_label.id}"
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
  name              = "${module.service_label.id}"
  retention_in_days = "${var.log_retention_in_days}"
  tags              = "${module.service_label.tags}"
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${module.task_label.id}"
  network_mode             = "${var.network_mode}"
  requires_compatibilities = ["${var.requires_compatibilities}"]
  execution_role_arn       = "${aws_iam_role.task_role.arn}"
  cpu                      = "${var.container_cpu}"
  memory                   = "${var.container_memory}"

  lifecycle {
    ignore_changes = ["container_definitions"]
  }

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.container_cpu},
    "environment": [{
      "name": "APACHE_HTTP_PORT_NUMBER",
      "value": "${var.container_port}"
    },
    {
      "name": "SERVICE_LOOKUP_NAME",
      "value": "${module.service_label.id}"
      }],
    "portMappings": [
      {
        "containerPort": ${var.container_port}
      }
    ],
    "essential": true,
    "image": "${var.container_image}",
    "memory": ${var.container_memory},
    "memoryReservation": ${var.container_memoryreservation},
    "name": "${module.task_label.id}",
    "NetworkMode": "${var.network_mode}",
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
  task_definition = "${module.task_label.id}"
  depends_on      = ["aws_ecs_task_definition.task"]
}

# ## Without ALB
# resource "aws_ecs_service" "web_service" {
#   count = "${var.create_alb ? 0 : 1 }"
#   name            = "${var.name}"
#   cluster         = "${var.cluster_id}"
#   task_definition = "${data.aws_ecs_task_definition.task.family}:${max("${aws_ecs_task_definition.task.revision}", "${data.aws_ecs_task_definition.task.revision}")}"
#   desired_count   = "${var.desired_count}"
#   deployment_maximum_percent = "${var.deployment_maximum_percent}"
#   deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
#   iam_role        = "${var.ecs_service_role_arn}"
#   launch_type     = "${var.launch_type}"
#   network_configuration {
#     security_groups = ["${var.security_group_ids}"]
#     subnets = ["${var.container_subnets}"]
#   }
#   placement_strategy {
#     type  = "spread"
#     field = "host"
#   }
#   lifecycle {
#     create_before_destroy = true
#   }
# }

## ALB

module "tg_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.5"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "tg"
  tags      = "${merge(map("ManagedBy", "Terraform"), var.tags)}"
}

resource "aws_alb_target_group" "main" {
  name                 = "${module.tg_label.id}"
  port                 = "${var.container_port}"
  protocol             = "${var.container_protocol}"
  vpc_id               = "${var.vpc_id}"
  deregistration_delay = "${var.deregistration_delay}"
  target_type          = "ip"

  health_check {
    path                = "${var.health_check_path}"
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    matcher             = "200-399"
  }

  tags = "${module.tg_label.tags}"
}

module "alb_label" {
  source = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.5"

  namespace = "${var.namespace}"
  stage     = "${var.stage}"
  name      = "alb"
  tags      = "${merge(map("ManagedBy", "Terraform"), var.tags)}"
}

resource "aws_alb" "main" {
  name            = "${module.alb_label.id}"
  subnets         = ["${var.alb_subnet_ids}"]
  security_groups = ["${aws_security_group.lb_sg.id}"]
  tags            = "${module.alb_label.tags}"
}

resource "aws_alb_listener" "front_end_ssl" {
  count             = "${var.certificate_arn == "" ? 0 : 1}"
  load_balancer_arn = "${aws_alb.main.id}"

  port            = "443"
  protocol        = "HTTPS"
  ssl_policy      = "ELBSecurityPolicy-2015-05"
  certificate_arn = "${var.certificate_arn}"

  default_action {
    target_group_arn = "${aws_alb_target_group.main.id}"
    type             = "forward"
  }

}

## No SSL
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"

  port     = "80"
  protocol = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.main.id}"
    type             = "forward"
  }
}

resource "aws_security_group" "lb_sg" {
  description = "controls access to the application ELB"

  vpc_id      = "${var.vpc_id}"
  name_prefix = "${module.alb_label.id}"

  lifecycle {
    ignore_changes = ["ingress"]
  }

  tags = "${module.alb_label.tags}"
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.lb_sg.id}"
}

resource "aws_security_group_rule" "allow_alb_in" {
  count                    = "${length(var.security_group_ids)}"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.lb_sg.id}"
  security_group_id        = "${element(var.security_group_ids, count.index)}"
}

# AWS Private DNS RECORDS

resource "aws_service_discovery_service" "service" {
  count = "${var.service_discovery_namespace_id == "NONE" ? 0 : 1}"
  name  = "${module.service_label.id}"

  dns_config {
    namespace_id = "${var.service_discovery_namespace_id}"

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

### Create the Task Role for the Container Task to run as.
resource "aws_iam_role" "task_role" {
  name = "${module.task_label.id}_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "execution_role_policy" {
  name = "${module.task_label.id}_role_policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
      ],
      "Resource": [
          "arn:aws:logs:*:*:*"
      ]
    }
  ]
}
EOF

  role = "${aws_iam_role.task_role.id}"
}


output "aws_cloudwatch_log_group" {
  value = "${aws_cloudwatch_log_group.main.name}"
}

output "service_name" {
  value = "${aws_ecs_service.default.name}"
}

output "targetgroup_arn" {
  value = "${aws_alb_target_group.main.arn}"
}

output "task_family" {
  value = "${aws_ecs_task_definition.task.family}"
}

output "alb_name" {
  value = "${aws_alb.main.name}"
}

output "alb_arn" {
  value = "${aws_alb.main.id}"
}

output "alb_securitygroup" {
  value = "${aws_security_group.lb_sg.id}"
}

output "alb_dns_name" {
  value = "${aws_alb.main.dns_name}"
}

output "alb_zone_id" {
  value = "${aws_alb.main.zone_id}"
}

output "certificate_arn" {
  value = "${var.certificate_arn}"
}
