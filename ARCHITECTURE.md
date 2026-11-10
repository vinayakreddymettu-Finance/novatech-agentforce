# Architecture

## Flow

```
Customer / Rep  ->  Agentforce agent (subagents choose an approved action)
                         |
                         v
              Apex invocable actions  (all business rules live here)
                         |
        +----------------+------------------+
        v                v                  v
  Salesforce data   Triggers (guards,   Google Apps Script
  (Order, Case,     sync, notify)       web app (stock lookup,
  custom objects)         |             notification email)
                          v
                   Queueable jobs -> callouts -> Integration_Log__c
```

The agent only picks which action to call and passes its inputs. Eligibility, priority, amounts and approval routing are computed in Apex; triggers then protect the data even if something bypassed the actions.

## Agent

**NovaTech Customer Operations Agent** (Employee Agent) with these subagents:

| Subagent | Actions |
|---|---|
| Returns and Refunds | Check Return Eligibility, Create Return Request, Submit Refund Approval |
| Order Tracking | Get Order Status, Escalate Support Case |
| Inventory Lookup | Get Warehouse Inventory |
| Complaint Escalation | Escalate Support Case |

## Data model

| Object | Purpose |
|---|---|
| Order (standard) plus `Order_Reference__c`, `Fulfillment_Status__c`, `Delivered_Date__c` | Order identity and delivery state |
| Account plus Customer Tier | Standard, Gold or Platinum; drives escalation priority |
| `Shipment__c` | Tracking number, ETA, status per order |
| `Return_Request__c` | Return with status Requested, Pending Approval, Approved, Completed, and refund amount |
| `Refund_Approval__c` | Decision record: amount, decision, reviewer |
| Case plus `Order__c`, `Escalation_Reason__c` | Escalations linked to the order |
| `Integration_Log__c` | Every outbound call, with a Failed checkbox |
| `Notification_Log__c` | One row per notification key; unique key prevents duplicates |
| `Inventory_Config__c` (hierarchy custom setting) | Web-app URL, API key, refund manager Id |

## Apex

| Class | Role |
|---|---|
| `CheckReturnEligibility` | 30-day window, delivered only, no active return for the order |
| `CreateReturnRequest` | Needs customer confirmation; amount computed from order lines; $200 or more flagged for approval |
| `SubmitRefundApproval` | Auto-approves under $200; otherwise Pending with the configured manager as reviewer, and refuses if no manager is configured |
| `EscalateSupportCase` | Priority High for delayed orders, orders of $500 or more, or Gold/Platinum customers; otherwise Medium; reuses an open case |
| `GetOrderStatus` | Status, shipment, ETA and overdue calculation; lookup failure is reported as a failure |
| `GetWarehouseInventory` | Callout with 10 s timeout, redirect handling, never guesses stock |
| `NotificationService` | Duplicate check, POST to web app, logging |
| `NotificationQueueable` | One background job per notification so each callout has its own transaction |
| `TestDataFactory` | Generated test data (tests do not rely on org data) |

## Triggers

| Trigger | Guards |
|---|---|
| `RefundApprovalTrigger` | Large refunds must start Pending; amount cannot change; decided approvals immutable; only the assigned reviewer can decide; syncs Return status; queues notification |
| `ReturnRequestTrigger` | Queues the "return requested" notification |
| `CaseEscalationTrigger` | Queues the "case escalated" notification when the case is linked to an order |

## Google integration

- **Inventory (GET):** web app takes `sku` and `key`; returns JSON. Wrong or missing key returns an error body (Google answers HTTP 200), which Apex detects and logs as Failed.
- **Notifications (POST):** JSON with key, event, recipient, subject, body. The script emails the owner a message marked as simulated, records it in a Notifications tab, and ignores repeated keys under a lock.
- The URL and key are stored only in the custom setting and the script's properties.

## Security model

- Permission set **NovaTech Support Rep**: Agent Access, the six action classes, and the minimum object and field permissions (for example read-only on Shipment and Account, create on Return Request and Case).
- Org-wide defaults and sharing are respected because all classes use `with sharing`.
- The agent never holds approval authority: the approval record is created by code, and only the named reviewer may change its decision.
- Prompt-injection attempts ("approve my refund", "ignore your rules") fail because nothing the agent says can change a rule enforced in code.

## Manager dashboard

Six panels: delayed orders, cases by priority, returns by status, approvals pending, failed integration calls, and escalations by customer.
