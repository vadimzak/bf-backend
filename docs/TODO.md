~ POD AWS Roles
~ implement Gamani
- update ALL packages to latest (incl AWS)
- add envs?
- add versioning and report it from the server
- rewrite sh scripts in ts?
~ Grafana + Loki + dashboards
- alerting
- make ECR only persist last 10 images
- ts-node -> tsx
- remove HTTP only mode
- fix deploy script to not require force rollout
- use real name from Google Auth
- run locally under same AWS permissions
- external DNS
- cleanup fallback flows deployment scripts
- make sure all packages are latest version
- security overview (incl AWS account)
- make sure only uses bf aws profile
- remove Route53CertbotAccess permission from sample-app-ec2-role role?