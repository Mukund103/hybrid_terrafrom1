provider "aws" {
  region = "us-east-1"
  profile = "mymukund"
}

//create security group to allow http port 
resource "aws_security_group" "allow_tls" {
  name        = "myfirstsg1"
  description = "Allow  inbound traffic for ssh and http"
  ingress {
    description = "SSH for admin Desktop"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP for client"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

//key-pair generation
resource "aws_key_pair" "deploy" {
  key_name   = "mukund"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAwkXnch3rg0oKUIt8v2iFYhDhuifqYjIxyrdJGzi7xCKWVjj2XSIWjnub9XCpQQ9JezYEYi55i3PlXgtN+P6bfuiwRnDnHpcr6xaA4KU+GQa2xHQdlrvYjqbqUKUmR39rsvJzM0yGLm1JvzNSxFC38uV2nCROWbZr0ShDM42BV1Odf00Av4MMJ6DOGG5UukMDJY9dOmDtRCzJbPDk32r4urLlbm3KjpR3s7WnwsMJzdDss3734uuB8ZB4MwV5HcT0IF2MlG9OTukdi6PmXkZCtwo2beZcGVm/fJ4Vu+nRPxKfVWtuFYvtlawqMBZcqahQyBrr9oL0f6tzlKWEAdeolQ== rsa-key-20200612"
} 

//Launch aws instance
resource "aws_instance" "web" {
  depends_on = [aws_key_pair.deploy, aws_security_group.allow_tls]
  ami           = "ami-09d95fab7fff3776c"
  instance_type = "t2.micro"
  security_groups=["myfirstsg1"]
  key_name="mukund"
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Mukund Kumar/Desktop/mukund.pem")
    host     = aws_instance.web.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd"
    ]
  }
  tags = {
    Name = "Webserver"
  }
}


//Create an EBS volume of 1GB
resource "aws_ebs_volume" "myebs" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "mywebebs"
  }
}

//Attach ebs volume "myebs" to your instances 
resource "aws_volume_attachment" "myebs_att" {
  depends_on = [aws_ebs_volume.myebs,aws_instance.web]
  device_name = "/dev/xvdb"
  volume_id   = aws_ebs_volume.myebs.id
  instance_id = aws_instance.web.id
  force_detach=true
}
resource "null_resource" "mounting" {
  depends_on = [aws_volume_attachment.myebs_att]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Mukund Kumar/Desktop/mukund.pem")
    host     = aws_instance.web.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdb",
      "sudo mount /dev/xvdb  /var/www/html",
      "sudo  rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Mukund103/aws_webserver.git  /var/www/html/"
    ]
  }

}



resource "null_resource" "local" {
  depends_on = [null_resource.mounting,null_resource.code_updating]
  provisioner "local-exec" {
    command = "start chrome ${aws_instance.web.public_ip}/lw.php"
  }
}




resource "aws_ebs_snapshot" "example_snapshot" {
  depends_on = [null_resource.local]
  volume_id = "${aws_ebs_volume.myebs.id}"

  tags = {
    Name = "HelloWorld_snap"
  }
  timeouts {
    create = "5m"
    delete = "2h"
  }
}





resource "aws_s3_bucket" "b" {
  bucket = "mukund1034"
  acl    = "public-read"
  force_destroy = true
}

resource "null_resource" "local3" {
  provisioner "local-exec" {
    command = "rd  /s /q web_image_s3"
  }
}

resource "null_resource" "local2" {
  depends_on = [null_resource.local3]
  provisioner "local-exec" {
    command = "git clone https://github.com/Mukund103/web_image_s3.git"
  }
}


resource "aws_s3_bucket_object" "object" {
  depends_on = [aws_s3_bucket.b]
  bucket = aws_s3_bucket.b.id
  key    = "IMG_9231.JPG"
  source = "./web_image_s3/IMG_9231.JPG"
  //etag = "${filemd5("./web_image_s3/IMG_9231.JPG")}"
  force_destroy = true
  acl    = "public-read"
  content_type="image/jpg"
}









resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on=[aws_s3_bucket_object.object]
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "mukund103"

  }
  enabled= true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "mukund103"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
    restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
    viewer_certificate {
    cloudfront_default_certificate = true
  }
}




resource "null_resource" "code_updating" {
  depends_on = [aws_cloudfront_distribution.s3_distribution]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Mukund Kumar/Desktop/mukund.pem")
    host     = aws_instance.web.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo chown ec2-user /var/www/html/lw.php",
      "sudo echo '''<img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/IMG_9231.JPG'  >'''  >>/var/www/html/lw.php"
    ]
  }

}