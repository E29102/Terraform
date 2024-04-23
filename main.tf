terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
  access_key = ""
  secret_key = ""

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
  vpc_id = aws_vpc.project_vpc.id

  route {
    cidr_block = "0.0.0.0/0" #Desination IP to private Subnet
    gateway_id = aws_internet_gateway.projectigw.id
  }

  tags = {
    Name = "Public route table"
  }
  depends_on = [aws_internet_gateway.projectigw]
}

#Initializes the private route table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.project_vpc.id

  route {
    cidr_block = "0.0.0.0/0" #Range for Desination IP to NAT gateway
    gateway_id = aws_nat_gateway.projectnatgw.id #Desination itself
  }

  tags = {
    Name = "Private route table"
  }
  depends_on = [aws_nat_gateway.projectnatgw]
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


resource "aws_security_group" "internal" {
  name        = "Internal SG"
  description = "SG for internal instances"
  vpc_id      = aws_vpc.project_vpc.id

  ingress {
    description = "ALL"
    from_port = 0
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.1.1.0/24"]
  }
  # ingress {
  #   description = "SSH"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["10.1.1.0/24"]
  # }


  egress {
    from_port   = 0
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.1.0/24"]
  }
  tags = {
    Name = "Internal SG"
  }
}

resource "aws_security_group" "external" {
  name        = "External SG"
  description = "SG for front facing instances"
  vpc_id      = aws_vpc.project_vpc.id

  # ingress {
  #   description = "ALL"
  #   from_port   = 0
  #   to_port     = 0
  #   protocol    = "-1"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  ingress {
    description = "SSH"
    from_port   = 0
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  egress {
    from_port   = 22
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  ingress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }



  tags = {
    Name = "External SG"
  }
}

resource "aws_instance" "PrivVM-FE" {
  ami           = "ami-06e85d4c3149db26a"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  vpc_security_group_ids      = ["${aws_security_group.internal.id}"]

  tags = {
    Name = "PrivVM-FE"
  }
  depends_on = [aws_subnet.private_subnet, aws_security_group.internal]
}

resource "aws_instance" "PrivVM-BE" {
  ami           = "ami-06e85d4c3149db26a"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  vpc_security_group_ids      = ["${aws_security_group.internal.id}"]

  tags = {
    Name = "PrivVM-BE"
  }
  depends_on = [aws_subnet.private_subnet, aws_security_group.internal]
}


resource "aws_instance" "PubVM" {
  ami           = "ami-06e85d4c3149db26a"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = ["${aws_security_group.external.id}"]

  tags = {
    Name = "PubVM"
 }
  depends_on = [aws_subnet.public_subnet, aws_security_group.external]
}

resource "aws_key_pair" "key"{
  public_key = file("./project_key.pub")
  key_name = "myKey"
}










