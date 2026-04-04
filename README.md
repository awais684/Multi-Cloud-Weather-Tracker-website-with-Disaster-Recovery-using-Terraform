# 🌤️ Multi-Cloud Weather Tracking Website with Disaster Recovery using Terraform

A production-ready, multi-cloud static website deployed on **AWS (Primary)** and **Azure (Secondary)** with automatic DNS failover using **Route 53**, **CloudFront CDN**, and **Azure Blob Storage** — all provisioned via **Terraform**.

---

## 📐 Architecture Diagram

```
                        ┌─────────────────────────────────────┐
                        │           AWS Cloud (PRIMARY)        │
                        │                                     │
User ──► Route 53 ──►  │   CloudFront CDN ──► S3 Bucket      │
         Hosted Zone    │   (HTTPS + SSL)     (Static Files)  │
                        └─────────────────────────────────────┘
                                      │
                              Health Check Fails?
                                      │
                                      ▼
                        ┌─────────────────────────────────────┐
                        │          Azure Cloud (SECONDARY)     │
                        │                                     │
                        │   Resource Group                    │
                        │   └── Storage Account              │
                        │       └── Static Website Hosting   │
                        └─────────────────────────────────────┘
```

> **Flow:** User visits domain → Route 53 checks health → Routes to AWS CloudFront (primary) → If AWS fails, automatically reroutes to Azure Blob Storage (secondary)

---

## 🛠️ Tech Stack

| Service | Purpose |
|---|---|
| **AWS S3** | Static website file hosting |
| **AWS CloudFront** | CDN + HTTPS termination |
| **AWS Route 53** | DNS management + failover routing |
| **AWS ACM** | SSL/TLS certificate |
| **Azure Blob Storage** | Secondary/failover static website |
| **Azure Resource Group** | Logical grouping of Azure resources |
| **Terraform** | Infrastructure as Code (IaC) |
| **Namecheap** | Domain registrar |

---

## 📋 Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed (v1.0+)
- AWS account with IAM user having admin permissions
- Azure account with an active subscription
- Domain name registered (e.g., from Namecheap)
- AWS CLI configured locally

---

## 🚀 Setup Steps

### Step 1: Buy and Register a Domain Name

Purchase a domain from [Namecheap](https://namecheap.com). Budget-friendly extensions like `.site`, `.online`, or `.tech` are available from as low as $1/year.

### Step 2: Request an SSL Certificate (ACM)

> ⚠️ **Must be in `us-east-1` region** — CloudFront only accepts ACM certs from N. Virginia.

1. Go to **AWS Certificate Manager → Request public certificate**
2. Add both `yourdomain.com` and `www.yourdomain.com`
3. Select **DNS validation**
4. Click **Create records in Route 53** to auto-validate
5. Wait for status to show **Issued** ✅

### Step 3: Create CloudFront Distribution (Console)

1. Go to **CloudFront → Create distribution**
2. Set origin to your S3 **website endpoint**: `bucket-name.s3-website-us-east-1.amazonaws.com`
3. Set **Viewer protocol policy** to `Redirect HTTP to HTTPS`
4. Add **Alternate domain names**: `yourdomain.com` and `www.yourdomain.com`
5. Attach the ACM certificate
6. Set **Default root object** to `index.html`
7. Deploy and copy the CloudFront domain (e.g., `xxxxx.cloudfront.net`)

### Step 4: Deploy Infrastructure with Terraform

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan -var-file="aws_credentials.tfvars" -var-file="azure_credentials.tfvars"

# Apply infrastructure
terraform apply -var-file="aws_credentials.tfvars" -var-file="azure_credentials.tfvars"
```

### Step 5: Update Namecheap Nameservers

1. Log in to Namecheap → **Domain List → Manage**
2. Under **Nameservers**, select **Custom DNS**
3. Enter your Route 53 NS records (from hosted zone), e.g.:
   ```
   ns-123.awsdns-45.com
   ns-234.awsdns-56.org
   ns-345.awsdns-67.net
   ns-456.awsdns-78.co.uk
   ```
4. Save and wait up to 30 minutes for DNS propagation

### Step 6: Verify DNS Propagation

Use [DNS Checker](https://dnschecker.org) to verify:
- `A` record for `yourdomain.com`
- `CNAME` record for `www.yourdomain.com`

---

## 📁 Project Structure

```
├── aws_resource.tf          # S3, CloudFront, Route 53, Health checks (AWS)
├── azure_resource.tf        # Storage account, Blob, Route 53 secondary records
├── aws_credentials.tfvars   # AWS credentials (gitignored)
├── azure_credentials.tfvars # Azure credentials (gitignored)
├── website/
│   ├── index.html
│   ├── styles.css
│   ├── script.js
│   └── assets/
└── README.md
```

---

## ⚙️ Key Terraform Resources

### AWS — Route 53 Failover Records

```hcl
# Primary — Apex domain pointing to CloudFront
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "yourdomain.com"
  type    = "A"
  alias {
    name                   = "xxxxx.cloudfront.net"
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = true
  }
  failover_routing_policy { type = "PRIMARY" }
  set_identifier  = "primary-root"
  health_check_id = aws_route53_health_check.aws_health_check.id
}

# Secondary — www pointing to Azure
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.yourdomain.com"
  type    = "CNAME"
  records = ["yourstorageaccount.z13.web.core.windows.net"]
  ttl     = 300
  failover_routing_policy { type = "SECONDARY" }
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.azure_health_check.id
}
```

### Azure — Static Website Storage

```hcl
resource "azurerm_storage_account" "storage" {
  name                     = "yourstorageaccount"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = "East US"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  static_website {
    index_document = "index.html"
  }
}
```

---

## 🔄 How Failover Works

1. Route 53 continuously runs **health checks** against the CloudFront endpoint every 30 seconds
2. If the health check fails **3 consecutive times**, Route 53 marks primary as unhealthy
3. DNS automatically routes all traffic to the **Azure Blob Storage** secondary endpoint
4. When AWS recovers, traffic is automatically routed back to primary

---

## ⚠️ Challenges & Solutions

### Challenge 1: S3 Bucket Policy — 403 AccessDenied
**Problem:** Terraform applied the bucket policy before disabling `BlockPublicPolicy`, causing a 403 error.

**Solution:** Added `depends_on` to ensure the public access block resource is applied before the bucket policy:
```hcl
resource "aws_s3_bucket_policy" "bucket_policy" {
  depends_on = [aws_s3_bucket_public_access_block.public_access]
  ...
}
```

---

### Challenge 2: Route 53 CNAME Conflict
**Problem:** Route 53 does not allow a `CNAME` record on the same DNS name where an `A` record already exists — resulted in `InvalidChangeBatch` error.

**Solution:** Ensured primary and secondary records for `www` use the same record type (`CNAME`). The apex domain (`yourdomain.com`) uses an `A` alias record pointing to CloudFront, while `www` uses `CNAME` for both primary and secondary.

---

### Challenge 3: Azure Alias Record Not Supported in Route 53
**Problem:** Attempted to use Route 53 `alias` block for Azure Blob Storage endpoint, but Route 53 alias only works with AWS services — no zone ID exists for Azure.

**Solution:** Used `CNAME` with `records` and `ttl` instead of an `alias` block for the Azure secondary record.

---

### Challenge 4: Azure Health Check Failing
**Problem:** Azure Blob static websites redirect HTTP → HTTPS internally, causing HTTP health checks to fail.

**Solution:** Changed Azure health check to use `HTTPS` on port `443`:
```hcl
resource "aws_route53_health_check" "azure_health_check" {
  type = "HTTPS"
  port = 443
  ...
}
```

---

### Challenge 5: ACM Certificate Region
**Problem:** CloudFront distributions only accept ACM certificates from the `us-east-1` region.

**Solution:** Always request the ACM certificate in **N. Virginia (us-east-1)** regardless of where other resources are deployed.

---

## 🧪 Testing Failover

To simulate a primary failure and test failover:

1. Go to **S3 → Block public access → Enable** (breaks CloudFront origin)
2. Wait 60–90 seconds for health check to detect failure (3 failed checks × 30 second interval)
3. Visit your domain — it should redirect to Azure
4. You may see an "HTTP" warning on Azure — this is **expected** (Azure Blob doesn't support HTTPS with custom domains without Azure CDN)
5. Re-enable S3 public access to restore primary

---

## 📌 Expected Behavior

| Scenario | Behavior |
|---|---|
| Normal operation | Traffic routed to AWS CloudFront (HTTPS ✅) |
| AWS primary fails | Traffic automatically reroutes to Azure (HTTP ⚠️) |
| Azure failover | Site remains functional, HTTP warning is expected |
| AWS recovers | Traffic automatically returns to primary |

> **Note:** The HTTP warning on Azure failover is expected behavior for this setup. In production, configure **Azure CDN** to enable HTTPS on custom domains.

---

## 🔐 Security Notes

- Never commit `aws_credentials.tfvars` or `azure_credentials.tfvars` to GitHub
- Add them to `.gitignore`:
  ```
  *credentials.tfvars
  .terraform/
  *.tfstate
  *.tfstate.backup
  ```
- Use IAM roles with least-privilege permissions in production

---

## 📄 License

This project is for educational purposes. Feel free to fork and adapt for your own multi-cloud projects.
