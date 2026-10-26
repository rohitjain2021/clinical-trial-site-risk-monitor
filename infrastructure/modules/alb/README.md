# Private Risk-Service ALB

Terraform owns an internal ALB in the existing EKS network. Its target group forwards to worker NodePort `30800`; an Auto Scaling traffic-source attachment registers replacement workers. The module does not own the EKS Auto Scaling group, worker instances, or shared network.

Dedicated security groups restrict HTTP clients and backend forwarding. A read-only, non-root verification job exercises the ALB using the shared synthetic HTTP verifier. The client group is reserved for later Lambda VPC integration.

Deploy through `infrastructure/live/dev/alb` after EKS and application outputs are updated. Destroy this unit before the application and EKS. See the [ALB guide](../../../docs/alb.md) for operator commands, private access, tests, running costs, and explicit teardown order.
