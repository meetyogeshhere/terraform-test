provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "my_treehouse" {
  ami           = "ami-0c55b159cbfafe1f0" # This is an Amazon Linux image (ask an adult to find the right AMI ID for your region)
  instance_type = "t2.micro"              # A small, free-tier computer
  tags = {
    Name = "MyCoolTreehouse"
  }
}
