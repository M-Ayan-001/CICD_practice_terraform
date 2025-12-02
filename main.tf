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

# setting inbound rules for security group
resource "aws_vpc_security_group_ingress_rule" "allow_tcp_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

# setting inbound rules for security group
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = aws_vpc.createVPC.cidr_block
  from_port         = 80
  ip_protocol       = "http"
  to_port           = 80
}

# setting outbound rules for security group
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



