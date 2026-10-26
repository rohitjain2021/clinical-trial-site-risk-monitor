# Assessment Notification Topic

Defines one project-named standard SNS topic, an HTTPS-only publishing policy, and one confirmation-required email subscription. The topic carries only minimal operational status events. The recipient is a sensitive input supplied by ignored local settings; no real address is committed.

The operator manages this unit separately from EKS and application state. Existing application IRSA policies grant only `sns:Publish` on the exact topic. This unit grants no public publisher access and introduces no extra compute or alarm resources.

See the [notification guide](../../../docs/notifications.md) for confirmation, deployment, monitoring, and demo steps. Topic creation and a successful publish do not establish inbox delivery.
