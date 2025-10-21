terraform {
  backend "s3" {
    bucket = "terraform-state-shantanu"   
    key    = "state/news-mvp.tfstate"
    region = "ap-south-1"
  }
}
