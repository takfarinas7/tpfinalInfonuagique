terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.95.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}



//creation vpc
resource "aws_vpc" "tpfinal" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "VPC-tpfinal"
  }
}

variable "vpc_cidr" {
  type        = string
  description = "Plages d'adresses du VPC"
  default     = "10.0.0.0/16"
}









//creation des sous reseaux
variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Plages d'adresses du sous-réseaux public"
  default     = ["10.0.0.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Plages d'adresses des sous-réseaux privé"
  default     = ["10.0.1.0/24"]
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["us-east-1a"]
}



resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.tpfinal.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)


  tags = {
    Name = "tpfinal-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.tpfinal.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)


  tags = {
    Name = "tpfinal-private-${count.index + 1}"
  }
}









//passerelle internet
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.tpfinal.id

  tags = {
    Name = "tpfinal-igw"
  }
}









//tables de routage

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.tpfinal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "tpfinal-rtb-public"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.tpfinal.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "tpfinal-rtb-private"
  }
}









//associer sous reseaux avec table de routage

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_route_table.private_rt.id
}












//creation groupe de securite
resource "aws_security_group" "ssh_access" {
  name        = "ssh-access"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.tpfinal.id

  ingress {

    description = "SSH"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "http_access" {
  name        = "http-access"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.tpfinal.id

  ingress {
    description = "HTTP"
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "https_access" {
  name        = "https-access"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.tpfinal.id

  ingress {
    description = "HTTPS"
    from_port   = "443"
    to_port     = "443"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}




//creation paire de clé
resource "aws_key_pair" "tpfinal_key" {
  key_name   = "tpfinal-keypair"
  public_key = tls_private_key.rsa.public_key_openssh
}

resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096

}

resource "local_file" "cluster_keypair" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "${path.module}/tpfinal-keypair.pem"
}






//creatoin instance
variable "ami_id" {
  type        = string
  description = "Id de l'AMI de l'instance"
  default     = "ami-084568db4383264d4"
  
}

variable "instance_type" {
  type        = string
  description = "Type de l'instance EC2"
  default     = "t2.large"
}

resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id                   = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.http_access.id, aws_security_group.ssh_access.id,aws_security_group.https_access.id]

  key_name = aws_key_pair.tpfinal_key.key_name

  root_block_device {
    volume_size = 64
    volume_type = "gp3"
  }

  tags = {
    Name = "web-server"
  
  }

  

  user_data = file("${path.module}/user-data.sh")

}




output "web_server_public_ip" {
  description = "Adresse IP publique du serveur web"
  value       = try(aws_instance.web_server.public_ip, "")
}



