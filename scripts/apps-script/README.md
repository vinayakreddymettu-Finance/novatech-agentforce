# Apps Script web app (inventory and notifications)

`Code.gs` is bound to the "NovaTech Inventory" Google Sheet.

- `doGet` returns stock for a SKU (needs `sku` and `key`).
- `doPost` records and emails a simulated notification and ignores repeated notification keys.

## Setup
1. Create a Sheet with an inventory tab (SKU, product name, quantity, warehouse, last updated).
2. Extensions > Apps Script, paste `Code.gs`.
3. Project Settings > Script Properties: add `API_KEY` with a long random value. Never put it in the code.
4. Deploy > New deployment > Web app, execute as you, access Anyone.
5. In Salesforce, store the web-app URL and the same key in the `Inventory_Config__c` custom setting, and add the URL as a Remote Site Setting. Do not commit either.
