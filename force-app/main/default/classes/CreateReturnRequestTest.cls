@IsTest
private class CreateReturnRequestTest {

    private static CreateReturnRequest.Request req(String ref, String code, String reason, Boolean confirmed) {
        CreateReturnRequest.Request r = new CreateReturnRequest.Request();
        r.orderReference = ref;
        r.productCode = code;
        r.reason = reason;
        r.customerConfirmed = confirmed;
        return r;
    }

    @IsTest
    static void refusesWithoutConfirmation() {
        TestDataFactory.makeOrder('T-2001', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 79 }, 'Standard');
        CreateReturnRequest.Result r = CreateReturnRequest.createOne(req('T-2001', TestDataFactory.code('T-2001', 1), 'Broken', false));
        Assert.isFalse(r.success);
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);
    }

    @IsTest
    static void smallRefundNeedsNoApproval() {
        TestDataFactory.makeOrder('T-2002', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 79 }, 'Standard');
        CreateReturnRequest.Result r = CreateReturnRequest.createOne(req('T-2002', TestDataFactory.code('T-2002', 1), 'Broken', true));
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.refundAmount == 79);
        Assert.isFalse(r.requiresApproval);
        Assert.isNotNull(r.returnRequestNumber);
        Assert.areEqual('Requested', [SELECT Status__c FROM Return_Request__c WHERE Id = :(Id) r.returnRequestId].Status__c);
    }

    @IsTest
    static void bigRefundNeedsApproval() {
        TestDataFactory.makeOrder('T-2003', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 899 }, 'Standard');
        CreateReturnRequest.Result r = CreateReturnRequest.createOne(req('T-2003', TestDataFactory.code('T-2003', 1), 'Damaged', true));
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.refundAmount == 899);
        Assert.isTrue(r.requiresApproval);
    }

    @IsTest
    static void approvalThresholdIsInclusiveAtTwoHundred() {
        TestDataFactory.makeOrder('T-2004', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 200 }, 'Standard');
        TestDataFactory.makeOrder('T-2005', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 199.99 }, 'Standard');
        CreateReturnRequest.Result atLimit = CreateReturnRequest.createOne(req('T-2004', TestDataFactory.code('T-2004', 1), 'x', true));
        CreateReturnRequest.Result below = CreateReturnRequest.createOne(req('T-2005', TestDataFactory.code('T-2005', 1), 'x', true));
        Assert.isTrue(atLimit.requiresApproval, '200 should need approval');
        Assert.isFalse(below.requiresApproval, '199.99 should not need approval');
    }

    @IsTest
    static void blankProductCodeReturnsWholeOrder() {
        TestDataFactory.makeOrder('T-2006', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 100, 150 }, 'Standard');
        CreateReturnRequest.Result r = CreateReturnRequest.createOne(req('T-2006', '', 'x', true));
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.refundAmount == 250);
        Assert.isTrue(r.requiresApproval);
    }

    @IsTest
    static void duplicateReturnIsRefused() {
        TestDataFactory.makeOrder('T-2007', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 79 }, 'Standard');
        CreateReturnRequest.Result first = CreateReturnRequest.createOne(req('T-2007', TestDataFactory.code('T-2007', 1), 'x', true));
        CreateReturnRequest.Result second = CreateReturnRequest.createOne(req('T-2007', TestDataFactory.code('T-2007', 1), 'x', true));
        Assert.isTrue(first.success);
        Assert.isFalse(second.success);
        Assert.areEqual(1, [SELECT COUNT() FROM Return_Request__c]);
    }

    @IsTest
    static void otherRefusals() {
        TestDataFactory.makeOrder('T-2008', 'Delivered', Date.today().addDays(-3), new List<Decimal>{ 79 }, 'Standard');
        TestDataFactory.makeOrder('T-2009', 'In Transit', null, new List<Decimal>{ 79 }, 'Standard');
        Assert.isFalse(CreateReturnRequest.createOne(req('T-2008', 'NOPE', 'x', true)).success, 'unknown product code');
        Assert.isFalse(CreateReturnRequest.createOne(req('T-2008', TestDataFactory.code('T-2008', 1), '', true)).success, 'blank reason');
        Assert.isFalse(CreateReturnRequest.createOne(req('T-2009', TestDataFactory.code('T-2009', 1), 'x', true)).success, 'not delivered');
        Assert.isFalse(CreateReturnRequest.createOne(req('', null, 'x', true)).success, 'blank order reference');
        Assert.areEqual(0, [SELECT COUNT() FROM Return_Request__c]);
    }
}