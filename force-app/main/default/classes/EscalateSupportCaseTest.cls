@IsTest
private class EscalateSupportCaseTest {

    private static EscalateSupportCase.Result escalate(String ref, String reason) {
        EscalateSupportCase.Request q = new EscalateSupportCase.Request();
        q.orderReference = ref;
        q.escalationReason = reason;
        return EscalateSupportCase.escalateOne(q);
    }

    @IsTest
    static void delayedOrderIsHighPriorityAndLinked() {
        Order o = TestDataFactory.makeOrder('T-5001', 'Delayed', null, new List<Decimal>{ 80 }, 'Standard');
        EscalateSupportCase.Result r = escalate('T-5001', 'Delivery is overdue');
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.created);
        Assert.areEqual('High', r.priority);
        Case c = [SELECT AccountId, ContactId, Order__c FROM Case WHERE Id = :(Id) r.caseId];
        Assert.areEqual(o.Id, c.Order__c);
        Assert.areEqual(o.AccountId, c.AccountId);
        Assert.areEqual(o.CustomerAuthorizedById, c.ContactId);
    }

    @IsTest
    static void highValueOrderIsHighPriority() {
        TestDataFactory.makeOrder('T-5002', 'Processing', null, new List<Decimal>{ 600 }, 'Standard');
        Assert.areEqual('High', escalate('T-5002', 'Customer upset').priority);
    }

    @IsTest
    static void goldTierCustomerIsHighPriority() {
        TestDataFactory.makeOrder('T-5003', 'Processing', null, new List<Decimal>{ 80 }, 'Gold');
        Assert.areEqual('High', escalate('T-5003', 'Customer upset').priority);
    }

    @IsTest
    static void ordinaryOrderIsMediumPriority() {
        TestDataFactory.makeOrder('T-5004', 'Processing', null, new List<Decimal>{ 80 }, 'Standard');
        Assert.areEqual('Medium', escalate('T-5004', 'Customer upset').priority);
    }

    @IsTest
    static void openCaseIsReusedNotDuplicated() {
        TestDataFactory.makeOrder('T-5005', 'Processing', null, new List<Decimal>{ 80 }, 'Standard');
        EscalateSupportCase.Result first = escalate('T-5005', 'First complaint');
        EscalateSupportCase.Result second = escalate('T-5005', 'Still upset');
        Assert.isTrue(first.created);
        Assert.isTrue(second.success);
        Assert.isFalse(second.created);
        Assert.areEqual(first.caseNumber, second.caseNumber);
        Assert.areEqual(1, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void closedCaseAllowsANewOne() {
        TestDataFactory.makeOrder('T-5006', 'Processing', null, new List<Decimal>{ 80 }, 'Standard');
        EscalateSupportCase.Result first = escalate('T-5006', 'First complaint');
        Case c = [SELECT Id, Status FROM Case WHERE Id = :(Id) first.caseId];
        c.Status = 'Closed';
        update c;
        EscalateSupportCase.Result second = escalate('T-5006', 'New problem');
        Assert.isTrue(second.created, second.message);
        Assert.areEqual(2, [SELECT COUNT() FROM Case]);
    }

    @IsTest
    static void invalidRequestsAreRefused() {
        TestDataFactory.makeOrder('T-5007', 'Processing', null, new List<Decimal>{ 80 }, 'Standard');
        Assert.isFalse(escalate('T-9999', 'x').success, 'unknown order');
        Assert.isFalse(escalate('T-5007', '').success, 'blank reason');
        Assert.isFalse(escalate('', 'x').success, 'blank order reference');
        Assert.areEqual(0, [SELECT COUNT() FROM Case]);
    }
}