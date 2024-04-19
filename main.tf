terraform {
  required_providers {
    aws = "hashicorp/aws"
    version = "4.53.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

#Initializes our VPC (Virtual Private Cloud)
resource "aws_vpc" "project_vpc" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "Project VPC"
  }
}

#Initializes our Public Subnet within the vpc
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet"
  }
}

#Initializes our Private Subnet within the vpc
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet"
  }
}

#Initializes our internet gateway within the vpc
resource "aws_internet_gateway" "projectigw" {
  vpc_id = aws_vpc.project_vpc.id

  tags = {
    Name = "Project IGW"
  }
}

#Initializes our elastic IP for our NAT within the vpc
resource "aws_eip" "static_ip" {
  vpc = true
  tags = {
    Name = "NAT GW Static IP"
  }
}

#Initializes the NAT gateway
resource "aws_nat_gateway" "projectnatgw" {
  allocation_id = aws_eip.static_ip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "Project NAT GW"
  }

  depends_on = [aws_internet_gateway.projectigw, aws_eip.static_ip]
}
#Initializes the public route table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.testvpc.id

  route {
    cidr_block = "10.1.2.0/24" #Desination IP to private Subnet
    gateway_id = aws_internet_gateway.projectigw.id
  }
  tags = {
    Name = "Public route table"
  }
  depends_on = [aws_internet_gateway.projectigw]
}

#Initializes the private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.testvpc.id

  route {
    cidr_block = aws_eip.static_ip #Desination IP to NAT gateway
    gateway_id = aws_nat_gateway.projectigw.id
  }
  tags = {
    Name = "Private route table"
  }
  depends_on = [aws_nat_gateway.projectigw]
}

#Bridging the gap between the public subnet and its routing table
resource "aws_route_table_association" "pub_to_ig" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
  depends_on     = [aws_internet_gateway.projectigw]
}

#Bridging the gap between the private subnet and its routing table
resource "aws_route_table_association" "priv_to_nat" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
  depends_on     = [aws_nat_gateway.projectnatgw]
}










