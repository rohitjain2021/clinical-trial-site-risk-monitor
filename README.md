# Clinical Trial Site Risk Monitor

Clinical trial site risk monitoring platform using AWS, Kubernetes, Snowflake, Terraform, Terragrunt, and AI-driven risk analysis.

## Development Setup

See the [development setup guide](docs/setup.md) for installation and verification instructions, starting with Terraform on Windows.

## Problem Statement

Clinical trials are often conducted across multiple hospitals, clinics, and research sites. Each site is expected to meet operational targets such as patient enrollment goals, study timelines, protocol compliance, and timely issue resolution.

Some sites may begin falling behind without the problem being immediately obvious. Slow enrollment, repeated delays, patient dropouts, protocol deviations, or unresolved operational issues can eventually affect the overall clinical trial timeline and increase cost.

### Example

Suppose a clinical trial site is expected to enroll **60 patients**, but it has enrolled only **21 patients**. The site is also **18 days behind schedule** and has **3 unresolved operational issues**.

This site may represent a higher operational risk and should receive attention before the problems become more serious.

## What We Are Trying to Solve

The goal of this project is to provide a simple **Clinical Trial Site Risk Monitor** that helps clinical operations teams quickly identify:

- which trial sites are performing normally
- which sites are beginning to fall behind
- which sites may represent a high risk
- the main reasons a site has been classified as risky

The application provides an easy way to review trial-site performance and detect potential problems earlier, helping teams focus attention on the sites that need it most.

## Architecture

![Clinical Trial Site Risk Monitor architecture showing the Streamlit UI, AWS services, Snowflake, and infrastructure management with Terraform and Terragrunt](docs/images/clinical-trial-site-risk-monitor-architecture.png)

Terragrunt manages environment configuration and orchestrates Terraform, which provisions the AWS infrastructure shown above.
