# creating VPC
resource "aws_vpc" "createVPC" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "CICD_VPC"
  }
}

# getting availability zones
data "aws_availability_zones" "available" {}

# creating some subnets
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.createVPC.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.createVPC.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

# Create Internet Gateway
resource "aws_internet_gateway" "createGateway" {
  vpc_id = aws_vpc.createVPC.id

  tags = { Name = "cicd-igw" }
}

# Create Route Table
resource "aws_route_table" "createRTB" {
  vpc_id = aws_vpc.createVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.createGateway.id
  }

  tags = {
    Name = "cicd-rtb"
  }
}

# Create Route Table Association for subnet1
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.createRTB.id
}

# Create Route Table Association for subnet2
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.createRTB.id
}

# creating security group for EC2
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.createVPC.id

  tags = {
    Name = "allow_tls"
  }
}

# setting inbound rules for EC2 security group
resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 22
  ip_protocol       = "ssh"
  to_port           = 22
}

# setting inbound rules for EC2 security group
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 80
  ip_protocol       = "http"
  to_port           = 80
}

# setting outbound rules for EC2 security group
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# creating EC2 instance
resource "aws_instance" "createEC2" {
  ami           = "ami-0ecb62995f68bb549"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet1.id

  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "cicd-ec2"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  vpc_security_group_ids = [
    aws_security_group.allow_tls.id
  ]
}

# creating key pair for SSH
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/deployer-key.pub")
}

# create target group
resource "aws_lb_target_group" "createTargetGroup" {
  name        = "cicd-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.createVPC.id
  target_type = "instance"
}

# create attachment of EC2 with target group
resource "aws_lb_target_group_attachment" "createTargetGroupAttachment" {
  target_group_arn = aws_lb_target_group.createTargetGroup.arn
  target_id        = aws_instance.createEC2.id
  port             = 80
}

# create security group for ALB
resource "aws_security_group" "allow_tls_alb" {
  name        = "allow_tls_alb"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.createVPC.id

  tags = {
    Name = "allow_tls_alb"
  }
}

# setting inbound rules for ALB security group
resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4_alb" {
  security_group_id = aws_security_group.allow_tls_alb.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 22
  ip_protocol       = "ssh"
  to_port           = 22
}

# setting inbound rules for ALB security group
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4_alb" {
  security_group_id = aws_security_group.allow_tls_alb.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 80
  ip_protocol       = "http"
  to_port           = 80
}

# setting outbound rules for ALB security group
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_alb" {
  security_group_id = aws_security_group.allow_tls_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# create ALB
resource "aws_lb" "createALB" {
  name               = "cicd-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls_alb.id]

  # ALB needs subnets in at least two different AZs
  subnets = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

# create listener
resource "aws_lb_listener" "createListener" {
  load_balancer_arn = aws_lb.createALB.arn
  port              = "80"
  protocol          = "HTTP"

  # This creates the rule: "Forward traffic on port 80 to my_target_group"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.createTargetGroup.arn
  }
}

# create WAF
resource "aws_wafv2_web_acl" "createWAF" {
  name        = "captcha-protection-acl"
  description = "WAF with CAPTCHA challenge for ALB"
  scope       = "REGIONAL" # Must be REGIONAL for ALBs (CLOUDFRONT is for CDN)

  default_action {
    allow {} # Allow traffic by default if it doesn't match the rule
  }

  # The Rule: Apply CAPTCHA to all traffic
  rule {
    name     = "CaptchaAllTraffic"
    priority = 1

    action {
      captcha {} # <--- The CAPTCHA Action
    }

    statement {
      # Condition: Match if the URL path starts with "/"
      # effectively matching 100% of HTTP requests.
      byte_match_statement {
        positional_constraint = "STARTS_WITH"
        search_string         = "/"
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CaptchaAllTraffic"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "main-acl-metrics"
    sampled_requests_enabled   = true
  }
}

# WAF association with ALB
resource "aws_wafv2_web_acl_association" "createWAFAssociation" {
  resource_arn = aws_lb.createALB.arn
  web_acl_arn  = aws_wafv2_web_acl.createWAF.arn
}
