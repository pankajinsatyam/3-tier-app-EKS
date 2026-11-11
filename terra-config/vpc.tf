locals {
  cluster_name = "Three-tier-cloud"
  azs          = ["us-east-1a", "us-east-1b"]
}
# 1. The VPC (your own private network)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # EKS needs this

  tags = {
    Name = "eks-vpc"
  }
}

# 2. Internet Gateway (the VPC's door to the internet)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "eks-igw"
  }
}

# 3. Public subnets (one per availability zone)
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24" # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "eks-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                      = "1" # internet-facing load balancers go here
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# 4. Private subnets (one per availability zone)
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 11}.0/24" # 10.0.11.0/24, 10.0.12.0/24
  availability_zone = local.azs[count.index]

  tags = {
    Name                                          = "eks-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1" # internal load balancers go here
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# 5. NAT Gateway (lets private subnets reach the internet, one-way)
#    Note: NAT Gateway is billed per hour. Destroy when not in use.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "eks-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # NAT must sit in a public subnet

  tags = {
    Name = "eks-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# 6. Route table for public subnets: internet traffic -> Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "eks-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 7. Route table for private subnets: internet traffic -> NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "eks-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# 8. Outputs (handy to see the IDs after apply)
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
