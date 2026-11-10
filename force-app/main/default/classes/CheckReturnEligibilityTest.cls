@IsTest
private class CheckReturnEligibilityTest {

    @IsTest
    static void eligibleWithinWindow() {
        TestDataFactory.makeOrder('T-1001', 'Delivered', Date.today().addDays(-5), new List<Decimal>{ 50 }, 'Standard');
        CheckReturnEligibility.Result r = CheckReturnEligibility.evaluate('T-1001');
        Assert.isTrue(r.eligible, r.reason);
    }

    @IsTest
    static void windowBoundaryIsDay30() {
        TestDataFactory.makeOrder('T-1002', 'Delivered', Date.today().addDays(-30), new List<Decimal>{ 50 }, 'Standard');
        TestDataFactory.makeOrder('T-1003', 'Delivered', Date.today().addDays(-31), new List<Decimal>{ 50 }, 'Standard');
        Assert.isTrue(CheckReturnEligibility.evaluate('T-1002').eligible, 'Day 30 should still be eligible');
        Assert.isFalse(CheckReturnEligibility.evaluate('T-1003').eligible, 'Day 31 should be outside the window');
    }

    @IsTest
    static void notDeliveredIsRefused() {
        TestDataFactory.makeOrder('T-1004', 'In Transit', null, new List<Decimal>{ 50 }, 'Standard');
        CheckReturnEligibility.Result r = CheckReturnEligibility.evaluate('T-1004');
        Assert.isFalse(r.eligible);
        Assert.isTrue(r.reason.contains('not been delivered'), r.reason);
    }

    @IsTest
    static void unknownAndBlankOrdersAreRefused() {
        CheckReturnEligibility.Result r1 = CheckReturnEligibility.evaluate('T-9999');
        Assert.isFalse(r1.eligible);
        Assert.isTrue(r1.reason.contains('No order was found'), r1.reason);
        Assert.isFalse(CheckReturnEligibility.evaluate('  ').eligible);
    }

    @IsTest
    static void existingActiveReturnBlocksNewOne() {
        Order o = TestDataFactory.makeOrder('T-1005', 'Delivered', Date.today().addDays(-5), new List<Decimal>{ 50 }, 'Standard');
        insert new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = 50, Status__c = 'Requested');
        CheckReturnEligibility.Result r = CheckReturnEligibility.evaluate('T-1005');
        Assert.isFalse(r.eligible);
        Assert.isTrue(r.reason.contains('already exists'), r.reason);
    }

    @IsTest
    static void rejectedReturnAllowsANewOne() {
        Order o = TestDataFactory.makeOrder('T-1006', 'Delivered', Date.today().addDays(-5), new List<Decimal>{ 50 }, 'Standard');
        insert new Return_Request__c(Order__c = o.Id, Reason__c = 'x', Refund_Amount__c = 50, Status__c = 'Rejected');
        Assert.isTrue(CheckReturnEligibility.evaluate('T-1006').eligible);
    }

    @IsTest
    static void invocableMethodReturnsOneResultPerRequest() {
        TestDataFactory.makeOrder('T-1007', 'Delivered', Date.today().addDays(-5), new List<Decimal>{ 50 }, 'Standard');
        CheckReturnEligibility.Request q = new CheckReturnEligibility.Request();
        q.orderReference = 'T-1007';
        List<CheckReturnEligibility.Result> out = CheckReturnEligibility.check(new List<CheckReturnEligibility.Request>{ q });
        Assert.areEqual(1, out.size());
        Assert.isTrue(out[0].eligible);
    }
}