# NovaTech Electronics: Agentforce Customer Operations

A customer-operations agent for a fictional electronics retailer, built on a Salesforce Developer Edition org with Agentforce. The agent answers order questions, handles returns and refunds, checks warehouse stock, escalates complaints, and sends (simulated) customer notifications. A manager dashboard reports on all of it.

**Core principle: the agent chooses among approved actions; Apex and triggers enforce every rule.** The agent never decides eligibility, priority, refund approval or amounts. It cannot be talked into bypassing a rule, because the rule is not in its prompt, it is in code.

## What it does

| Module | Capability | Enforced by |
|---|---|---|
| Order tracking | Order status, shipment, tracking number, ETA, overdue detection | `GetOrderStatus` |
| Returns | 30-day window, delivered orders only, no duplicate returns, customer must confirm before a return is created | `CheckReturnEligibility`, `CreateReturnRequest` |
| Refund approval | Under $200 auto-approved; $200 or more goes to a manager and can never be approved by the agent | `SubmitRefundApproval`, `RefundApprovalTrigger` |
| Inventory | Live stock lookup from a Google Sheet through an Apps Script web app | `GetWarehouseInventory` |
| Escalation | Case created with system-set priority; an open case for the same order is reused | `EscalateSupportCase` |
| Notifications | Simulated email on return, decision and escalation, with duplicate protection | `NotificationService`, `NotificationQueueable` |
| Dashboard | Six panels for the support manager | Reports + dashboard |

## Security and safeguards

- All classes are `with sharing`; the agent runs as the logged-in user, and a dedicated **NovaTech Support Rep** permission set grants only what that role needs.
- Refund approvals: amount locked after creation, decided approvals immutable, only the assigned reviewer can decide, large refunds must start as Pending.
- Duplicate prevention for returns, cases and notifications.
- Failure is stated plainly: if a lookup fails, the agent says so instead of inventing an answer ("no shipment" is never used to hide an error).
- Secrets (API key, web-app URL) live in a protected custom setting and Apps Script properties, are never logged, and are never committed to this repository.
- Every outbound call is recorded in `Integration_Log__c` with a Failed flag.

## Repository contents

| File | Purpose |
|---|---|
| `README.md` | This overview |
| `ARCHITECTURE.md` | Objects, classes, triggers, integration, security model |
| `TEST_PLAN.md` | Automated and manual test coverage |
| `DEMO_SCRIPT.md` | Step-by-step demo with expected results |

## Setup summary

1. Create a Salesforce Developer Edition org with Agentforce enabled.
2. Load the sample customers, products, orders and inventory (CSV files provided with the project).
3. Create the custom objects and fields listed in `ARCHITECTURE.md`.
4. Deploy the Apex classes and triggers.
5. Create the Google Sheet and Apps Script web app; store the web-app URL and API key in the `Inventory_Config__c` custom setting (never in source control) and add the Remote Site Setting.
6. Create the **NovaTech Support Rep** permission set, including Agent Access to the agent.
7. Create the agent, its subagents and the six actions; commit and activate the version.
8. Build the reports and dashboard.

## Results

- 53 automated unit tests, all passing, 92% overall Apex coverage.
- Verified manually as a restricted support-rep user, including prompt-injection attempts and deliberate integration failure.

## Known limitations

- Inventory lookup needs the exact SKU; a product-name-to-SKU lookup is a planned improvement.
- Notifications are simulated through email to the script owner, not sent to real customers.
- Actions are implemented in Apex rather than Flow.
