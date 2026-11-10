public with sharing class GetWarehouseInventory {

    private static final Integer TIMEOUT_MS = 10000;
    private static final String API_NAME = 'Warehouse Inventory (Google Apps Script)';
    private static final String UNAVAILABLE_MSG = 'The warehouse inventory system is temporarily unavailable, so stock could not be checked. Please try again later. Do not guess availability.';

    public class Request {
        @InvocableVariable(label='SKU' description='Product SKU such as LAP-1001' required=true)
        public String sku;
    }

    public class Result {
        @InvocableVariable(label='Lookup Succeeded' description='True if the warehouse system answered')
        public Boolean lookupSucceeded;
        @InvocableVariable(label='SKU Found')
        public Boolean skuFound;
        @InvocableVariable(label='SKU')
        public String sku;
        @InvocableVariable(label='Product Name')
        public String productName;
        @InvocableVariable(label='Available Quantity')
        public Integer availableQuantity;
        @InvocableVariable(label='In Stock')
        public Boolean inStock;
        @InvocableVariable(label='Warehouse')
        public String warehouse;
        @InvocableVariable(label='Last Updated')
        public String lastUpdated;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Get Warehouse Inventory' description='Looks up live stock for a SKU in the warehouse inventory sheet. Returns the real quantity, or a message that stock could not be checked. Never estimate stock.' callout=true)
    public static List<Result> getInventory(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Request req : requests) {
            results.add(lookupOne(req, logs));
        }
        if (!logs.isEmpty()) {
            insert logs;
        }
        return results;
    }

    public static Result lookupOne(Request req, List<Integration_Log__c> logs) {
        Result r = new Result();
        r.lookupSucceeded = false;
        r.skuFound = false;
        r.inStock = false;

        String sku = (req == null || req.sku == null) ? '' : req.sku.trim().toUpperCase();
        r.sku = sku;
        if (sku == '') {
            r.message = 'No SKU was provided.';
            return r;
        }

        Inventory_Config__c cfg = Inventory_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Web_App_URL__c) || String.isBlank(cfg.API_Key__c)) {
            logs.add(buildLog(0, 'Inventory settings are missing.'));
            r.message = UNAVAILABLE_MSG;
            return r;
        }
        String key = cfg.API_Key__c.trim();
        String url = cfg.Web_App_URL__c.trim()
            + '?sku=' + EncodingUtil.urlEncode(sku, 'UTF-8')
            + '&key=' + EncodingUtil.urlEncode(key, 'UTF-8');

        try {
            HttpResponse res = send(url);
            Integer hops = 0;
            while (isRedirect(res.getStatusCode()) && hops < 3 && !String.isBlank(res.getHeader('Location'))) {
                res = send(res.getHeader('Location'));
                hops++;
            }
            Integer code = res.getStatusCode();
            if (code != 200) {
                logs.add(buildLog(code, 'Unexpected HTTP status ' + code + ' from the inventory service.'));
                r.message = UNAVAILABLE_MSG;
                return r;
            }

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (body.containsKey('error')) {
                String err = String.valueOf(body.get('error'));
                if (err == 'SKU not found') {
                    logs.add(buildLog(code, null));
                    r.lookupSucceeded = true;
                    r.message = 'SKU ' + sku + ' was not found in the warehouse inventory.';
                } else {
                    logs.add(buildLog(code, 'The inventory service returned an error: ' + err));
                    r.message = UNAVAILABLE_MSG;
                }
                return r;
            }

            Integer qty = Integer.valueOf(String.valueOf(body.get('availableQuantity')));
            r.lookupSucceeded = true;
            r.skuFound = true;
            r.sku = String.valueOf(body.get('sku'));
            r.productName = String.valueOf(body.get('productName'));
            r.availableQuantity = qty;
            r.inStock = qty > 0;
            r.warehouse = String.valueOf(body.get('warehouse'));
            r.lastUpdated = String.valueOf(body.get('lastUpdated'));
            r.message = r.productName + ' (' + r.sku + '): ' + (qty > 0 ? qty + ' in stock' : 'out of stock')
                + ' at the ' + r.warehouse + ' warehouse (updated ' + r.lastUpdated + ').';
            logs.add(buildLog(code, null));
            return r;
        } catch (Exception e) {
            String msg = e.getMessage() == null ? 'Unknown error' : e.getMessage().replace(key, '***');
            logs.add(buildLog(0, e.getTypeName() + ': ' + msg));
            r.message = UNAVAILABLE_MSG;
            return r;
        }
    }

    private static HttpResponse send(String endpoint) {
        HttpRequest hr = new HttpRequest();
        hr.setEndpoint(endpoint);
        hr.setMethod('GET');
        hr.setTimeout(TIMEOUT_MS);
        return new Http().send(hr);
    }

    private static Boolean isRedirect(Integer code) {
        return code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
    }

    private static Integration_Log__c buildLog(Integer code, String err) {
        return new Integration_Log__c(
            API__c = API_NAME,
            Response_Code__c = code,
            Error__c = err,
            Failed__c = (err != null),
            Timestamp__c = System.now()
        );
    }
}