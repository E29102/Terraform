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
  access_key = 
  secret_key = 

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

#Initializes our Public Subnet within the vpc
resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PublicSubnet_2"
  }
}

#issue with variable not being imported from the emv.sh file

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
    cidr_blocks = ["0.0.0.0/0"] # ["10.1.1.0/24"]
  }
   ingress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  egress {
    
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Internal SG"
  }
}

resource "aws_security_group" "external" {
  name        = "External SG"
  description = "SG for front facing instances"
  vpc_id      = aws_vpc.project_vpc.id

  ingress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 0
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 22
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
  ami           = "ami-08116b9957a259459"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  vpc_security_group_ids      = ["${aws_security_group.internal.id}"]

  tags = {
    Name = "PrivVM-FE"
  }

  user_data = file("./fe-script.sh")
  user_data_replace_on_change = true
  depends_on = [aws_subnet.private_subnet, aws_security_group.internal]

}

resource "aws_instance" "PrivVM-BE" {
  ami           = "ami-08116b9957a259459"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.private_subnet.id
  associate_public_ip_address = false
  vpc_security_group_ids      = ["${aws_security_group.internal.id}"]

  tags = {
    Name = "PrivVM-BE"
  }
  user_data = file("./be-script.sh")
  user_data_replace_on_change = true
  depends_on = [aws_subnet.private_subnet, aws_security_group.internal]
}


resource "aws_instance" "PubVM" {
  ami           = "ami-08116b9957a259459"
  instance_type = "t3.micro"
  availability_zone = "us-west-2a"
  key_name = aws_key_pair.key.key_name
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  vpc_security_group_ids      = ["${aws_security_group.external.id}"]

  tags = {
    Name = "PubVM"
 }
 user_data = file("./fe-script.sh")
  user_data_replace_on_change = true
  depends_on = [aws_subnet.public_subnet, aws_security_group.external]
}

#Load balancer
resource "aws_lb" "public-lb" {
  name               = "public-lb-tf"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]

  enable_deletion_protection = false

  security_groups = [aws_security_group.internal.id]

  tags = {
    Environment = "production"
  }
}

#Target Groups for load balancer
#Front End
resource "aws_lb_target_group" "privFE-tg" {
  name        = "privFE-tg"
  port        = 5173
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.project_vpc.id

}

resource "aws_lb_target_group_attachment" "fe-ip"{
  target_group_arn = aws_lb_target_group.privFE-tg.arn
  target_id = aws_instance.PrivVM-FE.id
  port = 5173
}


#BackEnd
resource "aws_lb_target_group" "privBE-tg" {
  name        = "privBE-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.project_vpc.id

}

resource "aws_lb_target_group_attachment" "be-ip"{
  target_group_arn = aws_lb_target_group.privBE-tg.arn
  target_id = aws_instance.PrivVM-BE.id
  port = 8080
}

#Listeners
#Front End
resource "aws_lb_listener" "fe-listener"{
  load_balancer_arn = aws_lb.public-lb.arn
  port = 5173
  protocol = "HTTP"
  
  default_action{
    type = "forward"
    target_group_arn = aws_lb_target_group.privFE-tg.arn
  }
}

#Back End
resource "aws_lb_listener" "be-listener"{
  load_balancer_arn = aws_lb.public-lb.arn
  port = 8080
  protocol = "HTTP"
  
  default_action{
    type = "forward"
    target_group_arn = aws_lb_target_group.privBE-tg.arn
  }
}



resource "aws_key_pair" "key"{
  public_key = file("./project_key.pub")
  key_name = "myKey"
}










