# Terraform sample for ECS clusters

This configuration creates two ECS clusters using public Terraform AWS modules.

- **Proxy cluster** – runs a single EC2 instance with the Traefik proxy.
- **Web cluster** – hosts site containers with a one‑time migrator container.
- An S3 bucket and a Lambda function are created for each site defined in the `sites` variable.

The main Terraform files are located in the `infrastructure/` directory.
