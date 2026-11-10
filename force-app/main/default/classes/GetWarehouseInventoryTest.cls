@IsTest
private class GetWarehouseInventoryTest {

    private class Mock implements HttpCalloutMock {
        private Integer status;
        private String body;
        private Boolean fail;
        public Mock(Integer status, String body, Boolean fail) {
            this.status = status;
            this.body = body;
            this.fail = fail;
        }
        public HttpResponse respond(HttpRequest req) {
            if (fail) {
                throw new CalloutException('Read timed out for key TESTKEY123');
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        insert new Inventory_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Web_App_URL__c = 'https://script.google.com/macros/s/TEST/exec',
            API_Key__c = 'TESTKEY123'
        );
    }

    private static GetWarehouseInventory.Result lookup(String sku) {
        GetWarehouseInventory.Request q = new GetWarehouseInventory.Request();
        q.sku = sku;
        Test.startTest();
        List<GetWarehouseInventory.Result> out =
            GetWarehouseInventory.getInventory(new List<GetWarehouseInventory.Request>{ q });
        Test.stopTest();
        return out[0];
    }

    private static final String IN_STOCK_BODY =
        '{"sku":"LAP-1001","productName":"NovaBook Pro","availableQuantity":12,"warehouse":"Austin","lastUpdated":"2026-11-07T14:30:00Z"}';

    @IsTest
    static void inStock() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, IN_STOCK_BODY, false));
        GetWarehouseInventory.Result r = lookup('lap-1001');
        Assert.isTrue(r.lookupSucceeded);
        Assert.isTrue(r.skuFound);
        Assert.isTrue(r.inStock);
        Assert.areEqual(12, r.availableQuantity);
        Assert.areEqual('Austin', r.warehouse);
        List<Integration_Log__c> logs = [SELECT Response_Code__c, Error__c FROM Integration_Log__c];
        Assert.areEqual(1, logs.size());
        Assert.areEqual(200, logs[0].Response_Code__c);
        Assert.isNull(logs[0].Error__c);
    }

    @IsTest
    static void outOfStock() {
        String body = '{"sku":"HDP-3002","productName":"NovaBuds White","availableQuantity":0,"warehouse":"Austin","lastUpdated":"2026-11-07T14:30:00Z"}';
        Test.setMock(HttpCalloutMock.class, new Mock(200, body, false));
        GetWarehouseInventory.Result r = lookup('HDP-3002');
        Assert.isTrue(r.skuFound);
        Assert.isFalse(r.inStock);
        Assert.areEqual(0, r.availableQuantity);
    }

    @IsTest
    static void unknownSku() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"error":"SKU not found","sku":"ZZZ-0000"}', false));
        GetWarehouseInventory.Result r = lookup('ZZZ-0000');
        Assert.isTrue(r.lookupSucceeded);
        Assert.isFalse(r.skuFound);
        Assert.isFalse(r.inStock);
        Assert.isNull(r.availableQuantity);
    }

    @IsTest
    static void timeoutFailsSafely() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '', true));
        GetWarehouseInventory.Result r = lookup('LAP-1001');
        Assert.isFalse(r.lookupSucceeded);
        Assert.isFalse(r.skuFound);
        Assert.isFalse(r.inStock);
        Assert.isNull(r.availableQuantity);
        Assert.isTrue(r.message.contains('temporarily unavailable'));
        List<Integration_Log__c> logs = [SELECT Response_Code__c, Error__c FROM Integration_Log__c];
        Assert.areEqual(1, logs.size());
        Assert.areEqual(0, logs[0].Response_Code__c);
        Assert.isNotNull(logs[0].Error__c);
        Assert.isFalse(logs[0].Error__c.contains('TESTKEY123'), 'The API key must never appear in the log');
    }

    @IsTest
    static void serverErrorFailsSafely() {
        Test.setMock(HttpCalloutMock.class, new Mock(500, 'Internal Server Error', false));
        GetWarehouseInventory.Result r = lookup('LAP-1001');
        Assert.isFalse(r.lookupSucceeded);
        Assert.isNull(r.availableQuantity);
        List<Integration_Log__c> logs = [SELECT Response_Code__c, Error__c FROM Integration_Log__c];
        Assert.areEqual(500, logs[0].Response_Code__c);
        Assert.isNotNull(logs[0].Error__c);
    }

    @IsTest
    static void wrongKeyFailsSafely() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"error":"Unauthorized"}', false));
        GetWarehouseInventory.Result r = lookup('LAP-1001');
        Assert.isFalse(r.lookupSucceeded);
        Assert.isNull(r.availableQuantity);
        List<Integration_Log__c> logs = [SELECT Error__c FROM Integration_Log__c];
        Assert.isNotNull(logs[0].Error__c);
    }

    @IsTest
    static void missingSettingsFailsSafely() {
        delete [SELECT Id FROM Inventory_Config__c];
        GetWarehouseInventory.Result r = lookup('LAP-1001');
        Assert.isFalse(r.lookupSucceeded);
        Assert.isNull(r.availableQuantity);
        List<Integration_Log__c> logs = [SELECT Response_Code__c, Error__c FROM Integration_Log__c];
        Assert.areEqual(1, logs.size());
        Assert.isNotNull(logs[0].Error__c);
    }

    @IsTest
    static void blankSkuIsRejected() {
        GetWarehouseInventory.Result r = lookup('   ');
        Assert.isFalse(r.lookupSucceeded);
        Assert.areEqual('No SKU was provided.', r.message);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }
}